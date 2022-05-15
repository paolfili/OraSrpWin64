#!/usr/bin/perl -w
#
# Proxy for OraSRP to access trace files at remote machines

#
# Copyright: 2010-2011, Egor Starostin
#
# License:
# Permission to use, copy, distribute and sell this software and
# its documentation for any purpose is hereby granted without
# fee, provided that the above copyright notice appear in all
# copies and that both that copyright notice and this permission
# notice appear in supporting documentation.
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY
# KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE
# WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR
# PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS
# OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR
# OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR
# OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
# SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
#
#


use IO::Socket;
use Getopt::Std;
use strict;

use vars qw/ $opt_p $opt_m $opt_q $opt_h $VERSION /;
my($trcf, $trcd, $reqtype, $server_port, $server, $mask, $quiet, $client, $readdata, $block, @trcfiles);

$VERSION = '1';

getopts('qhp:m:');

if ($opt_h) {
    print "usage: perl proxysrp.pl [-h] [-p port] [-q] [-t traceid]\n";
    print "\noptions:\n";
    print "  -h\t\tshow this help message and exit\n";
    print "  -p port\tlisten on alternate port (instead of default 2503)\n";
    print "  -q\t\tbe quiet, report errors to stderr only\n";
    print "  -t traceid\tprocess files with traceid in their names only\n";
    exit;
}

$server_port = $opt_p || 2503;
$mask = $opt_m || '';
$quiet = $opt_q || 0;
$server = IO::Socket::INET->new(LocalPort => $server_port, Type => SOCK_STREAM, Reuse => 1, Listen => 10 )
    or die "Couldn't start server on port $server_port : $@\n";

print STDERR "INFO: listening on port $server_port\n" if (!$quiet);
while (1) {
    $client = $server->accept();
    $readdata = <$client>;
    $readdata =~ s/\r\n$//; $readdata =~ s/\n$//;
    $reqtype = '';
    if ($readdata =~ /^GET (.*)$/) {
        $reqtype = 'GET';
        $trcf = $1;
    } elsif ($readdata =~ /^LIST (.*)$/) {
        $reqtype = 'LIST';
        $trcd = $1;
    } elsif ($readdata =~ /^VERSION$/) {
        print $client "$VERSION\n";
        close($client);
        next;
    }
    if ($reqtype eq 'GET') {
        if (! -f $trcf) {
            print STDERR "ERROR: ignoring request for file '$trcf': it doesn't exist\n";
            print $client "ERROR file '$trcf' does not exist\n";
            close($client);
            next;
        }
        if (index($trcf,$mask) == -1) {
            print STDERR "ERROR: ignoring request for '$trcf': file doesn't match pattern '$mask'\n";
            print $client "ERROR file '$trcf' does not match the required pattern\n";
            close($client);
            next;
        }
        # usual GET block
        print STDERR "INFO: sending trace file '$trcf' to socket\n" if (!$quiet);
        if (open(TRCF,$trcf)) {
            print $client "OK   \n";
            while (read(TRCF,$block,65536)) {
                print $client $block;
            }
        } else {
            print $client "ERROR cannot open file '$trcf'\n";
        }
    }
    if ($reqtype eq 'LIST') {
        if (! -d $trcd) {
            print STDERR "ERROR: can't get list of '$trcd': directory doesn't exist\n";
            print $client "ERROR directory '$trcd' does not exist\n";
            close($client);
            next;
        }
        if (! opendir(DIR, $trcd)) {
            print STDERR "ERROR: can't open $trcd: $!\n";
            print $client "ERROR directory '$trcd' is not accessible\n";
            close($client);
            next;
        }
        @trcfiles = grep { /\.trc$/ && (index($_,$mask) != -1) && -f "$trcd/$_" } readdir(DIR);
        closedir DIR;
        foreach my $f (@trcfiles) {
            if (-f "$trcd/$f") {
                my (@x) = stat("$trcd/$f");
                print $client $x[7],"***",$x[9],"***",$f,"\n";
            }
        }
    }
    close($client);
}
close($server);
