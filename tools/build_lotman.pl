#!/usr/bin/perl
# Aligns Yu. M. Lotman's commentary with the text of "Евгений Онегин".
#
#   perl tools/build_lotman.pl build/lotman.html data/onegin.json
#
# Input:  the FEB page with the commentary (windows-1251 HTML, one paragraph per
#         line) and data/onegin.json produced by extract_onegin.pl.
# Output: data/lotman-map.json        - the correspondence file: which fragment of
#                                       the novel every entry of the commentary
#                                       refers to, and where the entry is on FEB.
#                                       It contains no text of the commentary.
#         local/lotman-comments.json  - the text of the entries, keyed by entry id.
#                                       For personal use only: the commentary is
#                                       under copyright, do not publish this file.
use strict;
use warnings;
use utf8;
use Encode qw(decode);
use JSON::PP;

binmode(STDERR, ':encoding(UTF-8)');

my ($html_file, $onegin_file) = @ARGV;
die "usage: build_lotman.pl lotman.html onegin.json\n" unless $onegin_file;

my $FEB = 'https://feb-web.ru/feb/pushkin/critics/lot/lot-472-.htm';

# ------------------------------------------------------------------ inputs --
my $onegin = do {
    open(my $f, '<:raw', $onegin_file) or die "$onegin_file: $!";
    local $/; JSON::PP->new->utf8->decode(<$f>);
};
my @src = do {
    open(my $f, '<:raw', $html_file) or die "$html_file: $!";
    local $/; split /\r?\n/, decode('cp1251', <$f>);
};

my %ROMAN = (I => 1, V => 5, X => 10, L => 50, C => 100);
sub roman {
    my ($s) = @_;
    my ($n, $prev) = (0, 0);
    for my $c (reverse split //, $s) {
        my $v = $ROMAN{$c} or return 0;
        $n += $v < $prev ? -$v : $v;
        $prev = $v if $v > $prev;
    }
    return $n;
}

# Onegin blocks: index by id and, per chapter, by stanza number.
my (%block, %stanza, %first_ep);
for my $p (@{ $onegin->{parts} }) {
    my $ch = $p->{n} // 0;
    my $last;
    for my $b (@{ $p->{blocks} }) {
        $block{ $b->{id} } = $b;
        $b->{_n} = [ grep { $_ ne '' } @{ $b->{lines} } ];      # numbered lines
        $first_ep{$ch} //= $b->{id} if $b->{kind} eq 'epigraph';
        next unless $b->{kind} eq 'stanza';
        my @nums = map { roman($_) } split /\. /, $b->{label};
        if (defined $last) {                                     # gaps -> previous block
            $stanza{$ch}{$_} //= $last->{id} for ($last->{_max} + 1 .. $nums[0] - 1);
        }
        $stanza{$ch}{$_} = $b->{id} for @nums;
        $b->{_max} = $nums[-1];
        $last = $b;
    }
}

# --------------------------------------------------------------- html utils --
sub plain {
    my ($h) = @_;
    $h =~ s/<a [^>]*class=footnote[^>]*>.*?<\/a>//g;
    $h =~ s/<[^>]+>//g;
    $h =~ s/&nbsp;/ /g; $h =~ s/&lt;/</g; $h =~ s/&gt;/>/g; $h =~ s/&amp;/&/g;
    $h =~ s/&raquo;/»/g; $h =~ s/&laquo;/«/g; $h =~ s/&bdquo;/„/g; $h =~ s/&ldquo;/“/g; $h =~ s/&rsquo;/’/g;
    $h =~ s/&eacute;/é/g; $h =~ s/&egrave;/è/g; $h =~ s/&agrave;/à/g; $h =~ s/&acirc;/â/g; $h =~ s/&ecirc;/ê/g;
    $h =~ s/&#x([0-9a-fA-F]+);/chr(hex($1))/ge; $h =~ s/&#(\d+);/chr($1)/ge;
    $h =~ s/\x{301}//g;                 # stress marks
    $h =~ s/\s+/ /g; $h =~ s/^ //; $h =~ s/ $//;
    return $h;
}

my %fn_used;
sub inline {                            # sanitise the inline markup of a paragraph
    my ($h, $fns) = @_;
    $h =~ s{<a href="#\$f(\w+)"[^>]*class=footnote[^>]*>(.*?)</a>}{ push @$fns, $1; "<sup class=\"fn\">$2</sup>" }ge;
    $h =~ s{<a href="#([^"]*)"[^>]*>}{<a href="$FEB?cmd=p#$1" target="_blank" rel="noopener">}g;
    $h =~ s{<(/?)em>}{<$1i>}g;
    $h =~ s{</?(?:font|span)[^>]*>}{}g;
    $h =~ s{<(?!/?(?:i|b|sup|sub|br|a)\b)[^>]*>}{}g;
    $h =~ s/\s+$//;
    return $h;
}

# ------------------------------------------------------------- pass 1: split --
my %footnote;
for (@src) { $footnote{$1} = $2 if /^<p id=\$f(\w+) class=snos>(.*)/; }

my %CH = ('Глава_первая' => 1, 'Глава_вторая' => 2, 'Глава_третья' => 3, 'Глава_четвертая' => 4,
          'Глава_пятая' => 5, 'Глава_шестая' => 6, 'Глава_седьмая' => 7, 'Глава_восьмая' => 8);
my $R  = qr/[IVXLCХІПШ]+/;
my $RS = qr/$R(?:\s*(?:[—–-]|\.)\s*$R)*/;
my $LN = qr/(?:\d{1,3}|[Il])(?:\s*[—–-]\s*\d{1,3})?/;

sub fix_roman { my ($s) = @_; $s =~ s/Х/X/g; $s =~ s/І/I/g; $s =~ s/П/II/g; $s =~ s/Ш/III/g; return $s; }

my (@entries, $e);
my ($in, $ch, $page, $anchor) = (0, undef, 0, '');
my ($ctx, $sect, $fresh) = (undef, '', 0);   # current block id; section kind; first paragraph of a section
my $after_break = 0;

sub start_entry {
    my (%a) = @_;
    $e = { ch => $ch, page => $page, anchor => $anchor, paras => [], fns => [], %a };
    push @entries, $e;
}

for my $l (@src) {
    if ($l =~ /^<h4 L=1 id=Комментарий /)                    { $in = 1; $ch = 0; $sect = 'front'; next; }
    if ($l =~ /^<h4 L=2 id=Комментарий\.Отрывки_из_путешествия/) { last; }
    if ($l =~ /<span class=page id=\$p(\d+)>/) { $page = $1; $anchor = "\$p$1"; $after_break = 1; next; }
    next unless $in;

    if ($l =~ /^<h([45]) L=(\d) id=(\S+) title="([^"]*)"/) {
        my ($lvl, $id, $title) = ($2, $3, $4);
        $anchor = $id;
        if ($lvl == 2) {
            (my $k = $id) =~ s/^Комментарий\.//;
            if (defined $CH{$k}) { $ch = $CH{$k}; $ctx = undef; $sect = 'chapter'; $fresh = 1; }
        } elsif ($lvl == 3) {
            $fresh = 1;
            if    ($title =~ /Эпиграф/)   { $sect = 'epigraph'; }
            elsif ($title =~ /Преамбула/) { $sect = $ch ? 'chapter' : 'front'; }
            else {
                $sect = 'stanza';
                (my $t = fix_roman($title)) =~ s/_.*//;
                my ($first) = $t =~ /^([IVXLC]+)/;
                $ctx = $stanza{$ch}{ roman($first) } if $first && $stanza{$ch}{ roman($first) };
            }
        }
        next;
    }

    # paragraphs (incl. the table rows of the chapter 7 epigraph)
    my ($class, $body);
    if    ($l =~ /^<p class=([\w-]+)[^>]*>(.*)/)        { ($class, $body) = ($1, $2); }
    elsif ($l =~ /^<tr><td[^>]*><p class=str>(.*)/)     { ($class, $body) = ('str', $1); }
    elsif ($l =~ /^<td><p class=(stix\d)[^>]*>(.*)/)    { ($class, $body) = ($1, $2); }
    elsif ($l =~ /^<br>(.*)/)                           { ($class, $body) = ('stix0', $1); }
    else { next; }
    next if $class =~ /^zagol/ || $body !~ /\S/;

    my $text = plain($body);
    my $started = 0;

    if ($ch == 0) {
        # preamble of the commentary: title, subtitle, main epigraph, dedication
        my %front = ('Евгений Онегин' => 'title', 'Роман в стихах' => 'subtitle',
                     'Pétri de vanité' => 'epigraph', 'Не мысля гордый свет забавить' => 'dedication');
        if ($body =~ /^<i>(Евгений Онегин|Роман в стихах|P&eacute;tri de vanit&eacute;|Не мысля гордый свет забавить)/) {
            my $k = plain($1);
            start_entry(scope => $front{$k}, ref => '');
            $started = 1;
        }
    } elsif ($class =~ /^text(?:1|0-1)$/ || $fresh) {
        if ($class =~ /^text/ && $text =~ /^($RS)\.?\s*,\s*($LN)\s*[—–]\s*(.*)$/) {
            my ($rs, $ln) = (fix_roman($1), $2);
            $ln =~ s/[Il]/1/;
            my @r = $rs =~ /([IVXLC]+)/g;
            my @n = $ln =~ /(\d+)/g;
            $ctx = $stanza{$ch}{ roman($r[0]) } // $ctx;
            start_entry(scope => 'lines', block => $ctx, lines => [ $n[0], $n[-1] ], ref => "$rs, $ln", head => 1);
            $started = 1;
        } elsif ($class =~ /^text/ && $text =~ /^($RS)\.?\s*[—–]\s+(.*)$/) {
            my $rs = fix_roman($1);
            my @r = $rs =~ /([IVXLC]+)/g;
            my $from = @r ? $stanza{$ch}{ roman($r[0]) } : undef;
            my $to   = @r ? $stanza{$ch}{ roman($r[-1]) } // $from : undef;
            if ($from) {
                $ctx = $from;
                start_entry(scope => 'stanza', block => $from, to => $to, ref => $rs);
                $started = 1;
            }
        } elsif ($class =~ /^text/ && $text =~ /^(Письмо Татьяны к Онегину|Песня девушек|Письмо Онегина к Татьяне)\.?\s*[—–]\s/) {
            my %b = ('Письмо Татьяны к Онегину' => '3.tatiana', 'Песня девушек' => '3.song', 'Письмо Онегина к Татьяне' => '8.onegin');
            $ctx = $b{$1};
            start_entry(scope => 'block', block => $ctx, ref => $1);
            $started = 1;
        } elsif ($class =~ /^text/ && $ctx && $body =~ /<i>/ && $text =~ /^($LN)\s*[—–]\s*(.*)$/) {
            my $ln = $1; $ln =~ s/[Il]/1/;
            my @n = $ln =~ /(\d+)/g;
            if ($n[-1] <= @{ $block{$ctx}{_n} } + 1) {
                start_entry(scope => 'lines', block => $ctx, lines => [ $n[0], $n[-1] ], ref => $ln, head => 1);
                $started = 1;
            }
        }
        if (!$started && $fresh) {
            if    ($sect eq 'epigraph') { start_entry(scope => 'epigraph', block => $first_ep{$ch}, ref => 'Эпиграф'); }
            elsif ($sect eq 'chapter')  { start_entry(scope => 'chapter', ref => ''); }
            # chapters 2-8 open with a section titled "<Эпиграф>" but ids ending in ".0"
            $started = 1 if $sect eq 'epigraph' || $sect eq 'chapter';
        }
    }
    $fresh = 0;
    next unless $e;

    # collect the paragraph
    my $kind = $class =~ /^stix[34]/ ? 'src' : $class =~ /^stix/ ? 'v' : $class eq 'str' ? 'v' : 'p';
    my $h = inline($body, $e->{fns});
    my $last = $e->{paras}[-1];
    if ($class eq 'text0' && $after_break && $last && $last->[0] eq 'p' && !$started) {
        $last->[1] .= " $h";                       # paragraph continued over a page break
    } else {
        push @{ $e->{paras} }, [ $kind, $h, $class eq 'text0' || $class eq 'text0-1' ? 1 : 0 ];
    }
    $e->{first} //= $body if $started;
    $after_break = 0;
}

# In chapters 2-8 the first section (id "….0") is the commentary on the epigraph.
for my $x (@entries) {
    next unless $x->{scope} eq 'chapter' && $x->{ch} > 1;
    $x->{scope} = 'epigraph'; $x->{block} = $first_ep{ $x->{ch} }; $x->{ref} = 'Эпиграф';
}

# ---------------------------------------------------------- pass 2: aligning --
sub norm_map {              # letters only, lower case; map back to offsets in the line
    my ($s) = @_;
    my (@map, $n);
    $n = '';
    my $masked = $s;
    $masked =~ s/(\{\d+\}|\[\d+\])/' ' x length($1)/ge;
    for my $i (0 .. length($masked) - 1) {
        my $c = lc substr($masked, $i, 1);
        $c = 'е' if $c eq 'ё';
        next unless $c =~ /[a-zа-яàâçéèêëîïôûùüÿœæ0-9]/;
        $n .= $c; push @map, $i;
    }
    return ($n, \@map);
}

sub approx {                # best approximate occurrence of $p in $t: (dist, start, end)
    my ($p, $t, $from) = @_;
    my ($n, $m) = (length $p, length $t);
    my @pc = split //, $p; my @tc = split //, $t;
    my (@d, @s);
    for my $j (0 .. $m) { $d[$j] = 0; $s[$j] = $j; }
    for my $i (1 .. $n) {
        my ($pd, $ps) = ($d[0], $s[0]);
        $d[0] = $i; $s[0] = 0;
        for my $j (1 .. $m) {
            my ($cd, $cs) = ($d[$j], $s[$j]);
            my ($bd, $bs) = ($pd + ($pc[$i - 1] eq $tc[$j - 1] ? 0 : 1), $ps);
            if ($cd + 1 < $bd)        { ($bd, $bs) = ($cd + 1, $cs); }
            if ($d[$j - 1] + 1 < $bd) { ($bd, $bs) = ($d[$j - 1] + 1, $s[$j - 1]); }
            ($pd, $ps) = ($cd, $cs);
            $d[$j] = $bd; $s[$j] = $bs;
        }
    }
    my ($best, $bj) = ($n + 1, 0);
    for my $j ($from .. $m) {
        next if $s[$j] < $from;
        ($best, $bj) = ($d[$j], $j) if $d[$j] < $best;
    }
    return ($best, $s[$bj], $bj);
}

# Find the fragments of a lemma in lines $a..$b of a block (in order).
sub locate {
    my ($b, $a, $z, $frags) = @_;
    my @spans;
    my ($li, $pos) = ($a, 0);
    for my $f (@$frags) {
        my ($fn) = norm_map($f);
        next if length($fn) < 2;
        my @best;
        for my $i ($li .. $z) {
            my ($tn, $map) = norm_map($b->{_n}[$i - 1] // '');
            my $from = $i == $li ? $pos : 0;
            next if $from >= length $tn;
            my ($d, $s, $t);
            my $ix = index($tn, $fn, $from);
            if ($ix >= 0) { ($d, $s, $t) = (0, $ix, $ix + length $fn); }
            else          { ($d, $s, $t) = approx($fn, $tn, $from); }
            next if $t <= $s;
            my $limit = length($fn) < 5 ? 0 : int(length($fn) * 0.25);
            next if $d > $limit;
            @best = ($d, $i, $s, $t, $map) if !@best || $d < $best[0];
            last if $d == 0;
        }
        if (!@best && $z > $li) {               # the quotation runs over a line end
            my ($cat, @where) = ('');
            for my $i ($li .. $z) {
                my ($tn, $map) = norm_map($b->{_n}[$i - 1] // '');
                for my $k (0 .. length($tn) - 1) { push @where, [ $i, $map->[$k] ]; }
                $cat .= $tn;
            }
            my ($d, $s, $t) = approx($fn, $cat, 0);
            if ($t > $s && $d <= int(length($fn) * 0.2) && $where[$s][0] != $where[$t - 1][0]) {
                for my $i ($where[$s][0] .. $where[$t - 1][0]) {
                    my @k = grep { $where[$_][0] == $i } $s .. $t - 1;
                    push @spans, [ $i, $where[ $k[0] ][1], $where[ $k[-1] ][1] + 1 ] if @k;
                }
                ($li, $pos) = ($where[$t - 1][0], 1e9);
                next;
            }
        }
        return undef unless @best;
        my (undef, $i, $s, $t, $map) = @best;
        push @spans, [ $i, $map->[$s], $map->[$t - 1] + 1 ];
        ($li, $pos) = ($i, $t);
    }
    return @spans ? \@spans : undef;
}

sub fragments { my ($l) = @_; return [ grep { /\w/ } split m{\s*/\s*|\.{2,}|…}, $l ]; }

# Candidate lemmas for an entry: the italic quotation after the reference, and
# the text up to the first / second / third dash (the lemma itself may contain one).
sub candidates {
    my ($x) = @_;
    my $html = $x->{first};
    my $rest = plain($html);
    $rest =~ s/^(?:$RS\.?\s*,\s*)?$LN\s*[—–]\s*//;                 # "II, 5 — lemma", "6—13 — lemma"
    my @c;
    my ($it) = $html =~ m{<i>(.*?)</i>};
    my $italic = defined $it ? plain($it) : '';
    for my $t ($italic, $rest) {
        my @pieces = split /\s*[—–]\s+/, $t;
        for my $k (1 .. (@pieces < 3 ? scalar @pieces : 3)) {
            my $cand = join(' — ', @pieces[0 .. $k - 1]);
            push @c, $cand if length($cand) > 1 && length($cand) <= 200;
        }
    }
    return ($italic, @c);
}

sub best_match {            # the candidate that covers most of the text
    my ($b, $a, $z, @cands) = @_;
    my ($lemma, $spans, $score) = (undef, undef, 0);
    for my $cand (@cands) {
        my $fr = fragments($cand);
        next unless @$fr;
        my $sp = locate($b, $a, $z, $fr) or next;
        my $s = 0; $s += $_->[2] - $_->[1] for @$sp;
        ($lemma, $spans, $score) = ($cand, $sp, $s) if $s > $score;
    }
    return ($lemma, $spans);
}

my (%stat, %redirect);
for my $x (@entries) {
    next unless $x->{scope} eq 'lines';
    if ($x->{head}) { %redirect = (); }
    elsif ($redirect{ $x->{block} }) { $x->{block} = $redirect{ $x->{block} }; }
    my $b = $block{ $x->{block} } or do { warn "no block for $x->{ch} $x->{ref}\n"; next; };
    my ($a, $z) = @{ $x->{lines} };
    my $max = @{ $b->{_n} };
    my ($italic, @cands) = candidates($x);

    my ($lemma, $spans);
    ($lemma, $spans) = best_match($b, $a, $z, @cands) if $a >= 1 && $z <= $max && $a <= $z;
    if ($spans) {
        $stat{located}++;
    } else {
        # not in the stated lines: a misnumbered line, or (rarely) a misprinted stanza number
        ($lemma, $spans) = best_match($b, 1, $max, @cands) if $max;
        my @long = grep { length((norm_map($_))[0]) >= 12 } @cands;
        if (!$spans && @long) {
            my @hit;
            for my $o (grep { $_->{id} =~ /^$x->{ch}\./ && $_->{kind} ne 'epigraph' } values %block) {
                my ($l, $s) = best_match($o, 1, scalar @{ $o->{_n} }, @long);
                push @hit, [ $o, $l, $s ] if $s;
            }
            if (@hit == 1) {
                $redirect{ $x->{block} } = $hit[0][0]{id};
                warn "stanza  $x->{ch} [$x->{ref}] $x->{block} -> $hit[0][0]{id}: $italic\n";
                ($b, $lemma, $spans) = @{ $hit[0] };
                $x->{block} = $b->{id};
            }
        }
        if ($spans) {
            $stat{moved}++;
            warn "moved   $x->{ch} [$x->{ref}] $x->{block} -> lines $spans->[0][0]-$spans->[-1][0]: $lemma\n";
            $x->{lines} = [ $spans->[0][0], $spans->[-1][0] ];
        } elsif ($a <= 1 && $z >= $max) {
            $stat{stanza}++;                    # "XXV, 1—14 — ..." is a note on the whole stanza
            $x->{scope} = 'stanza'; $x->{to} = $x->{block};
            next;
        } else {
            # no quotation to look for: mark the first line of the passage
            $stat{unlocated}++;
            $max ||= 1;
            ($a, $z) = (($a < 1 ? 1 : $a > $max ? $max : $a), ($z > $max ? $max : $z < 1 ? 1 : $z));
            $x->{lines} = [ $a, $z ];
            $spans = [ [ $a, 0, length($b->{_n}[$a - 1] // '') ] ];
            $lemma = $italic;
            warn "nolemma $x->{ch} [$x->{ref}] $x->{block}: $italic\n";
        }
    }
    $lemma =~ s/(\.\.\.|…)\s+[—–]\s.*$/$1/;     # keep the quotation, drop what follows it
    $lemma =~ s/^[\s—–]+//; $lemma =~ s/\s+$//;
    $x->{lemma} = $lemma;
    $x->{spans} = $spans;
}

# ------------------------------------------------------------------- output --
my (%seen, @map, %text);
for my $x (@entries) {
    my $id;
    if    ($x->{scope} eq 'lines')  { $id = "$x->{block}:" . ($x->{lines}[0] == $x->{lines}[1] ? $x->{lines}[0] : "$x->{lines}[0]-$x->{lines}[1]"); }
    elsif ($x->{scope} eq 'stanza') { $id = $x->{block} . ($x->{to} ne $x->{block} ? "~" . (split /\./, $x->{to}, 2)[1] : ''); }
    elsif ($x->{scope} eq 'block')  { $id = $x->{block}; }
    elsif ($x->{scope} eq 'epigraph' && $x->{ch}) { $id = "$x->{ch}.ep"; }
    elsif ($x->{scope} eq 'chapter') { $id = "$x->{ch}.intro"; }
    else                            { $id = "0.$x->{scope}"; }
    $id .= chr(ord('a') + $seen{$id}) if $seen{$id}++;
    $x->{id} = $id;

    my %m = (id => $id, ch => $x->{ch} + 0, scope => $x->{scope}, page => $x->{page} + 0, anchor => $x->{anchor});
    $m{ref}   = $x->{ref} if $x->{ref} ne '';
    $m{block} = $x->{block} if $x->{block};
    $m{block} = '0.ep'  if $x->{scope} eq 'epigraph' && !$x->{ch};
    $m{block} = '0.ded' if $x->{scope} eq 'dedication';
    $m{to}    = $x->{to} if $x->{to} && $x->{to} ne $x->{block};
    if ($x->{scope} eq 'lines') {
        # the reference as "stanza, lines" (Lotman gives the stanza once per group of entries)
        my $b = $block{ $x->{block} };
        (my $st = $b->{label} // $b->{title}) =~ s/^(Письмо \S+).*/$1/;
        $m{ref} = "$st, " . join('—', $x->{lines}[0] == $x->{lines}[1] ? $x->{lines}[0] : @{ $x->{lines} });
        $m{lines} = [ map { $_ + 0 } @{ $x->{lines} } ];
        $m{lemma} = $x->{lemma};
        $m{spans} = [ map { [ map { $_ + 0 } @$_ ] } @{ $x->{spans} } ];
    }
    push @map, \%m;

    # text of the entry (local file only)
    my ($out, $verse) = ('', 0);
    for my $p (@{ $x->{paras} }) {
        my ($k, $h, $cont) = @$p;
        if ($k eq 'p') {
            if ($verse) { $out .= '</div>'; $verse = 0; }
            $out .= ($cont ? '<p class="c">' : '<p>') . $h . '</p>';
        } else {
            if (!$verse) { $out .= '<div class="v">'; $verse = 1; } else { $out .= '<br>'; }
            $out .= $k eq 'src' ? "<span class=\"src\">$h</span>" : $h;
        }
    }
    $out .= '</div>' if $verse;
    for my $f (@{ $x->{fns} }) {
        next unless defined $footnote{$f};
        my $t = $footnote{$f};
        $t =~ s{^<sup><a [^>]*>(.*?)</a></sup>}{<sup>$1</sup>};
        $out .= '<p class="fn">' . inline($t, []) . '</p>';
    }
    $text{$id} = $out;
}

my $json = JSON::PP->new->utf8->canonical;
sub write_file { my ($f, $s) = @_; open(my $o, '>:raw', $f) or die "$f: $!"; print $o $s; close $o; }

my $head = {
    title   => 'Лотман Ю. М. Роман А. С. Пушкина «Евгений Онегин». Комментарий',
    edition => 'Лотман Ю. М. Пушкин: Биография писателя; Статьи и заметки, 1960—1990; «Евгений Онегин»: Комментарий. — СПб.: Искусство-СПБ, 1995. — С. 472—762.',
    url     => $FEB,
};
# one entry per line: readable diffs, still plain JSON
write_file('data/lotman-map.json',
    "{\n\"source\": " . $json->encode($head) . ",\n\"entries\": [\n"
    . join(",\n", map { $json->encode($_) } @map) . "\n]\n}\n");

mkdir 'local';
write_file('local/lotman-comments.json',
    $json->encode({ format => 'onegin-lotman-comments/1', source => $head, comments => \%text }));

my %by; $by{ $_->{scope} }++ for @map;
warn sprintf("entries: %d (%s)\n", scalar @map, join(', ', map { "$_: $by{$_}" } sort keys %by));
warn sprintf("lemma located: %d, found on other lines: %d, turned into stanza notes: %d, not located: %d\n",
    map { $stat{$_} // 0 } qw(located moved stanza unlocated));
