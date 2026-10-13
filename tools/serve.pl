#!/usr/bin/perl
# A tiny static file server for reading the site locally:
#
#   perl tools/serve.pl          ->  http://localhost:8765/
#
# (The page loads its data with fetch(), which does not work from file://.)
use strict;
use warnings;
use IO::Socket::INET;
use IO::Select;
use File::Basename qw(dirname);
use Cwd qw(abs_path);

my $port = shift // 8765;
my $root = abs_path(dirname(__FILE__) . '/..');
my %type = (html => 'text/html; charset=utf-8', css => 'text/css; charset=utf-8',
            js => 'text/javascript; charset=utf-8', json => 'application/json; charset=utf-8',
            txt => 'text/plain; charset=utf-8', svg => 'image/svg+xml', png => 'image/png', ico => 'image/x-icon');

my $srv = IO::Socket::INET->new(LocalAddr => '127.0.0.1', LocalPort => $port, Listen => 32, ReuseAddr => 1)
    or die "cannot listen on port $port: $!\n";
$| = 1;
print "Serving $root at http://localhost:$port/\n";

# Browsers open several connections at once and leave some idle, so the
# sockets are multiplexed instead of being served one after another.
my $sel = IO::Select->new($srv);
my %buf;
while (1) {
    for my $s ($sel->can_read) {
        if ($s == $srv) {
            my $c = $srv->accept or next;
            $sel->add($c); $buf{$c} = '';
            next;
        }
        my $n = sysread($s, $buf{$s}, 8192, length $buf{$s});
        if ($n && $buf{$s} !~ /\r?\n\r?\n/) { next; }            # request not complete yet
        respond($s, $buf{$s}) if $n;
        $sel->remove($s); delete $buf{$s}; close $s;
    }
}

sub respond {
    my ($c, $req) = @_;
    my ($path) = $req =~ m{^GET\s+(\S+)};
    $path //= '/';
    $path =~ s/[?#].*//;
    $path =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/ge;
    $path .= 'index.html' if $path =~ m{/$};
    my $file = "$root$path";
    my ($ext) = $file =~ /\.(\w+)$/;
    if ($path !~ /\.\./ && -f $file && open(my $f, '<:raw', $file)) {
        local $/; my $body = <$f>;
        print $c "HTTP/1.0 200 OK\r\nContent-Type: " . ($type{ lc($ext // '') } // 'application/octet-stream')
               . "\r\nContent-Length: " . length($body) . "\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n", $body;
    } else {
        print $c "HTTP/1.0 404 Not Found\r\nContent-Type: text/plain\r\nContent-Length: 9\r\nConnection: close\r\n\r\nNot found";
    }
}
