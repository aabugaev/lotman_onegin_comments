#!/usr/bin/perl
# Builds data/onegin.json from the PDF edition of "Евгений Онегин".
#
#   pdftotext -enc UTF-8 -simple "А. Пушкин евгений Онегин.pdf" build/onegin_simple.txt
#   perl tools/extract_onegin.pl build/onegin_simple.txt > data/onegin.json
#
# Only the novel itself is kept: title pages, publisher's annotation, table of
# contents, running headers and page numbers are dropped.
use strict;
use warnings;
use utf8;
use JSON::PP;

binmode(STDOUT, ':raw');
binmode(STDERR, ':encoding(UTF-8)');

my $src = shift or die "usage: extract_onegin.pl onegin_simple.txt\n";
open(my $fh, '<:encoding(UTF-8)', $src) or die "$src: $!";
my @raw = <$fh>;
close $fh;

my $HEADER = qr/^\s*А\. С\. Пушкин\. «Евгений Онегин»\s*$/;
my $ROMAN  = qr/[IVXL]+/;
my %ORD = (первая => 1, вторая => 2, третья => 3, четвертая => 4,
           пятая => 5, шестая => 6, седьмая => 7, восьмая => 8);
# Attribution lines that close an epigraph.
my $ATTR = qr/^(?:Tiré d’une lettre particulière|Кн\. Вяземский|Hor\.|Malfilâtre|Necker|Жуковский|Petr\.|Дмитриев|Баратынский|Грибоедов|Byron)\{?\d*\}?$/;

# ---------------------------------------------------------------- pass 1 ----
# Split into pages, strip headers / page numbers, pull out editor's footnotes
# (translations of foreign phrases) and mark their references in the text.
my (@pages, @cur);
for my $l (@raw) {
    $l =~ s/\r?\n$//;
    if ($l =~ s/\f//g) { push @pages, [@cur]; @cur = (); }
    push @cur, $l;
}
push @pages, [@cur];

my %footnotes;
my $next_fn = 1;
my @lines;          # cleaned stream: text lines, '' for blank, "\x01" for page break
for my $pg (@pages) {
    my @p = @$pg;
    @p = grep { $_ !~ $HEADER } @p;
    # page number: last non-blank line, far to the right
    for (my $i = $#p; $i >= 0; $i--) {
        next if $p[$i] =~ /^\s*$/;
        splice(@p, $i, 1) if $p[$i] =~ /^\s{30,}\d+\s*$/;
        last;
    }
    # footnotes: from the first "  N text" line (N = next expected number) to page end
    my @page_fn;
    for (my $i = 0; $i < @p; $i++) {
        if ($p[$i] =~ /^\s{0,12}(\d+) (\S.*)$/ && $1 == $next_fn) {
            my @tail = splice(@p, $i);
            my $n;
            for my $t (@tail) {
                if ($t =~ /^\s{0,12}(\d+) (\S.*)$/ && $1 == $next_fn) {
                    $n = $1; $footnotes{$n} = $2; push @page_fn, $n; $next_fn++;
                } elsif ($t =~ /\S/ && defined $n) {
                    $t =~ s/^\s+//; $footnotes{$n} .= " $t";
                }
            }
            last;
        }
    }
    # mark the references: a number glued to the preceding word, e.g. "vale2,"
    for my $n (@page_fn) {
        my $done = 0;
        for my $t (@p) {
            if ($t =~ s/(?<=[^\s\d\[\{])$n(?![\d\]\}])/{$n}/) { $done = 1; last; }
        }
        warn "footnote $n: reference not found\n" unless $done;
    }
    push @lines, @p, "\x01";
}
for my $n (keys %footnotes) {
    for ($footnotes{$n}) {
        s/\s+/ /g; s/\s+$//;
        s/([,.])(?=[А-ЯЁA-Z])/$1 /g;      # lines glued together by the PDF
        s/ – / — /g;
    }
}

# ---------------------------------------------------------------- pass 2 ----
sub clean {
    my ($t) = @_;
    $t =~ s/^\s+//; $t =~ s/\s+$//; $t =~ s/\s{2,}/ /g;
    $t =~ s/^– /— /; $t =~ s/ –(?= |$)/ —/g;      # en dash -> em dash
    $t =~ s/l’ Abbé/l’Abbé/;
    $t =~ s/^О rus!/O rus!/;                    # Cyrillic "О" in the PDF
    return $t;
}

my (@parts, $part, $block, %notes);
my $mode = 'skip';      # skip | front | epigraph | body | notes | done
my $blank = 0;          # blank line seen since the last text line
my $pagebreak = 0;      # page break seen since the last text line
my $note_n;

sub new_part  { $part = { @_, blocks => [] }; push @parts, $part; $block = undef; }
sub new_block { $block = { @_, lines => [] }; push @{ $part->{blocks} }, $block; }

for my $l (@lines) {
    if ($l eq "\x01") { $pagebreak = 1; next; }
    if ($l !~ /\S/)   { $blank = 1; next; }
    my $t = clean($l);

    if ($mode eq 'skip') {
        next unless $t =~ /^Pétri de vanité/;
        new_part(id => 'front', title => undef);
        new_block(id => '0.ep', kind => 'epigraph');
        $mode = 'epigraph';
    }
    if ($mode eq 'done') {
        if ($t =~ /^Примечания А\. С\. Пушкина/) { $mode = 'notes'; }
        next;
    }
    if ($mode eq 'notes') {
        if ($t =~ /^(\d+)\.$/) { $note_n = $1; $notes{$note_n} = ''; next; }
        next unless defined $note_n;
        $notes{$note_n} .= ($notes{$note_n} eq '' ? '' : ' ') . $t;
        next;
    }

    if ($t eq 'КОНЕЦ') { $mode = 'done'; next; }

    if ($t =~ /^Глава (\S+)$/ && $ORD{$1}) {
        my $n = $ORD{$1};
        new_part(id => "ch$n", n => $n, title => $t);
        $mode = 'epigraph';
        $block = undef;
        ($blank, $pagebreak) = (0, 0);
        next;
    }

    # stanza heading: "XV", "XIII. XIV", "I. II. III."
    if ($part->{n} && $t =~ /^($ROMAN(?:\.\s*$ROMAN)*)(\.?)$/) {
        my ($label, $dot) = ($1, $2); $label =~ s/\.\s*/. /g;
        $mode = 'body';
        ($blank, $pagebreak) = (0, 0);
        # A heading ending with a dot continues on the next line ("VIII." / "IX." / "X").
        # Chapter 4 opens with the omitted stanzas I-VI, which stay a block of their own.
        if ($block && $block->{kind} eq 'stanza' && $block->{open} && !@{ $block->{lines} }
            && !($part->{n} == 4 && $label eq 'VII')) {
            $block->{label} .= ". $label";
        } else {
            new_block(kind => 'stanza', label => $label);
        }
        $block->{open} = $dot;
        next;
    }

    # inserted pieces with their own heading
    if ($t =~ /^(ПИСЬМО ТАТЬЯНЫ К ОНЕГИНУ|ПЕСНЯ ДЕВУШЕК|ПИСЬМО ОНЕГИНА К ТАТЬЯНЕ)$/) {
        my %h = ('ПИСЬМО ТАТЬЯНЫ К ОНЕГИНУ' => ['tatiana', 'Письмо Татьяны к Онегину'],
                 'ПЕСНЯ ДЕВУШЕК'            => ['song',    'Песня девушек'],
                 'ПИСЬМО ОНЕГИНА К ТАТЬЯНЕ' => ['onegin',  'Письмо Онегина к Татьяне']);
        new_block(id => "$part->{n}.$h{$t}[0]", kind => 'verse', title => $h{$t}[1]);
        ($blank, $pagebreak) = (0, 0);
        next;
    }

    if ($mode eq 'epigraph') {
        if (!$block || $block->{kind} ne 'epigraph' || defined $block->{attr}) {
            my $k = 1 + grep { $_->{kind} eq 'epigraph' } @{ $part->{blocks} };
            new_block(id => ($part->{n} // 0) . '.ep' . ($k > 1 ? $k : ''), kind => 'epigraph');
        }
        if ($t =~ $ATTR) {
            $block->{attr} = $t;
            if ($part->{id} eq 'front') {       # the dedication follows the main epigraph
                new_block(id => '0.ded', kind => 'verse', title => undef);
                $mode = 'body';
            }
        } else {
            push @{ $block->{lines} }, $t;
        }
        ($blank, $pagebreak) = (0, 0);
        next;
    }

    # body text
    die "text outside of a block: $t\n" unless $block;
    if ($block->{kind} eq 'verse' && @{ $block->{lines} }
        && (($blank && !$pagebreak) || $t =~ /^Другой!\.\. Нет, никому/)) {
        push @{ $block->{lines} }, '';          # paragraph break inside a letter / song
    }
    push @{ $block->{lines} }, $t;
    ($blank, $pagebreak) = (0, 0);
}

for (values %notes) { s/ – / — /g; }

# ---------------------------------------------------------- post-processing --
# Chapter 4: the PDF prints a stray "XXXVII" before stanza XXXV; the stanza
# headed "XXXVI" is the canonical "XXXVI. XXXVII".
for my $p (grep { ($_->{n} // 0) == 4 } @parts) {
    my $b = $p->{blocks};
    for (my $i = 0; $i < $#$b; $i++) {
        if ($b->[$i]{kind} eq 'stanza' && $b->[$i]{label} eq 'XXXVII'
            && !@{ $b->[$i]{lines} } && $b->[$i + 1]{label} eq 'XXXV') {
            splice(@$b, $i, 1);
            $_->{label} = 'XXXVI. XXXVII' for grep { ($_->{label} // '') eq 'XXXVI' } @$b;
            last;
        }
    }
}

# "Stepped" lines: one verse printed in two rows (a change of speaker). The PDF
# gives them as two lines; glue them back with "\n" so that line numbers match
# the canonical 14-line stanza.
sub syllables {
    my ($t) = @_;
    $t =~ s/\{\d+\}|\[\d+\]//g;
    my $n = () = $t =~ /[аеёиоуыэюяАЕЁИОУЫЭЮЯaeiouyAEIOUYéèêàâîôûÉ]/g;
    return $n;
}
for my $p (@parts) {
    for my $b (@{ $p->{blocks} }) {
        delete $b->{open};
        next unless $b->{kind} eq 'stanza';
        my $l = $b->{lines};
        while (@$l > 14) {
            my ($best, $bi);
            for my $i (0 .. $#$l - 1) {
                my $s = syllables($l->[$i]) + syllables($l->[$i + 1]);
                ($best, $bi) = ($s, $i) if !defined $best || $s < $best;
            }
            last if $best > 12;
            warn "  joined in $p->{id}.$b->{label}: $l->[$bi] | $l->[$bi + 1]\n";
            splice(@$l, $bi, 2, "$l->[$bi]\n$l->[$bi + 1]");
        }
        # The PDF shortens two combined headings; restore the canonical numbering.
        $b->{label} = q{XV. XVI. XVII} if $p->{n} == 6 && $b->{label} eq q{XV};
        $b->{label} = q{XXXIX. XL}     if $p->{n} == 7 && $b->{label} eq q{XXXIX};
        (my $key = $b->{label}) =~ s/\. /-/g;
        $b->{id} = "$p->{n}.$key";
    }
}

# ------------------------------------------------------------- diagnostics --
for my $p (@parts) {
    for my $b (@{ $p->{blocks} }) {
        next unless $b->{kind} eq 'stanza';
        my $n = @{ $b->{lines} };
        warn "  $b->{id}: $n lines\n" if $n != 14;
    }
}
warn sprintf("parts: %d, blocks: %d, footnotes: %d, notes: %d\n",
    scalar @parts, (eval { my $c = 0; $c += @{ $_->{blocks} } for @parts; $c }),
    scalar keys %footnotes, scalar keys %notes);

my $out = {
    title     => 'Евгений Онегин',
    subtitle  => 'Роман в стихах',
    author    => 'Александр Сергеевич Пушкин',
    parts     => \@parts,
    footnotes => \%footnotes,
    notes     => \%notes,
};
print JSON::PP->new->utf8->canonical->pretty->indent_length(1)->encode($out);
