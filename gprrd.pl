#!/usr/bin/perl -w
use strict;
use warnings;
use diagnostics;
use Data::Dumper;
use File::Basename;
use File::Find;
use Getopt::Long;
Getopt::Long::Configure('bundling');
use List::Util qw[min max];
use Pod::Usage;
use Sys::Hostname;
use Sys::Syslog qw(:DEFAULT setlogsock);
use POSIX;
use Time::Local;

my $HOME = $ENV{'HOME'};
$ENV{'PATH'} = "$HOME/bin:/usr/bin:/bin";

# Setup logging:
my $prog_name = uc(basename($0));
openlog($prog_name,'pid','local6');

# Setup script meta info:
my $scriptruntime = localtime();
my $hostname=hostname;
my $scriptversion = "FIXMEVERSION";

# Default return code.
my $rtn_code = 0;

# Setup command-line options:
my ($help, $man, $version, $verbose, $debug, $type);
my ($sd, $ed, $pstr, $rrdhome, $listfile, $outpath, $test);
GetOptions (
    'help'              => \$help,
    'man'               => \$man,
    'version'           => \$version,
    'verbose'           => \$verbose,
    'debug'             => \$debug,
    't|formattype=s'    => \$type,
    'sd=s'              => \$sd,
    'ed=s'              => \$ed,
    'P|pstr=s'          => \$pstr,
    'H|rrdhome=s'       => \$rrdhome,
    'L|list=s'          => \$listfile,
    'O|outpath=s'       => \$outpath,
    'test'              => \$test
) or die pod2usage(1);
pod2usage(2) if $help;
pod2usage(-verbose => 2) if $man;

if (defined($debug)) {
        print "DEBUG: prog_name=$prog_name\n";
        print "DEBUG: scriptruntime=$scriptruntime\n";
        print "DEBUG: hostname=$hostname\n";
}

if (defined($version)) {
        print $scriptversion, "\n";
        exit 0;
}

# 
# COLORS
my $color_seagreen = "1BE08E";
my $color_brightgreen = "7AFC00";
my $color_green = "1FAB70";
my $color_teal = "03FCBE";
my $color_yellow = "FCFC00";
my $color_orange = "FC7200";
my $color_red = "FC0D00";
my $color_pink = "F57DD9";
my $color_blue = "0032FC";
my $color_brightblue = "00FCD2";
my $color_magenta = "E300FC";
my $color_purple = "8F00FC";
my $color_black = "000000";
my $color_navyblue = "0E1E96";


# 
# EXAMPLE EPOCH TIMES:
my $epoch_day =84600; # (one day)
#my $epoch_172800 (two days)
#my $epoch_259200 (three days)
#my $epoch_604800 (seven days)
#my $epoch_1209600 (14 days)
#my $epoch_2592000 (30 days)

unless(defined($pstr)) {
    $pstr = "dm03";
}
my $rrdbin = "/sw/bin/rrdtool";
my $rrd_cmd = $rrdbin . " graph ";

unless(defined($outpath)) {
    $outpath = $HOME . "/rrd";
}

if (! -e $outpath) {
    `mkdir -p $outpath`;
}

unless(defined($rrdhome)) {
    $rrdhome = $HOME . "/rrd";
}

unless(defined($listfile)) {
    $listfile = $HOME . "/lists/all.txt";
}

if (defined($sd)) {
    $sd = $epoch_day * $sd;
}else {
    $sd = $epoch_day * "14";
}

if (defined($ed)) {
    $ed = $epoch_day * $ed;
} else {
    $ed = $epoch_day;
}

##############################
# Functions
##############################
sub yesterday {
	my $dayshift = shift;
	$dayshift = $dayshift * (-1);
	my $type = shift;
	my $oneday = $epoch_day * $dayshift;
	my $epoch = timelocal(localtime) - $oneday;
	my $yest;
	if (defined($type)) {
        	if ($type eq "1") {
	        	$yest=strftime("%m/%d/%Y",localtime($epoch));
	        } elsif ($type eq "2") {
	                $yest=strftime("%m%d",localtime($epoch));
	        } elsif ($type eq "3") {
	                $yest=strftime("%a %b %d %H:%M:%S %Z %Y",localtime($epoch));
	        } elsif ($type eq "4") {
	                $yest=strftime("%m%d%Y",localtime($epoch));
	        } elsif ($type eq "5") {
	                $yest=strftime("%b_%d",localtime($epoch));
	        } else {
	                print "Please use a correct type format.\n";
	                pod2usage(2);
	        }
	} else {
       	 $yest=strftime("%m/%d/%Y",localtime($epoch));
	}
	return $yest;
}

sub commifylist {
	(@_ == 0) ? ''  	:
	(@_ == 1) ? $_[0]	:
	(@_ == 2) ? join(",",@_):
	join(",", @_[0 .. ($#_-1)], "$_[-1]");
};


##############################
# Main
##############################
#   vpiavg 
#       color = (blue)
#       upperlimit = 
#       lowerlimit = 0
my $y = &yesterday(-1,5);



my $h;
open(LISTFILE,$listfile) or die "Can't open $listfile: $!\n";
WHILELISTFILE: while (<LISTFILE>) {
    chomp;
    next WHILELISTFILE if m/^#/;
    next WHILELISTFILE if m/^$/;
    $h->{$_}->{'CPU'}->{'ul'}                           = "100";
    $h->{$_}->{'CPU'}->{'ll'}                           = "0";
    $h->{$_}->{'CPU'}->{'cpuidle'}->{'color'}                   = $color_red;
    $h->{$_}->{'CPU'}->{'cpuidle'}->{'fill'}                    = "LINE";

	$h->{$_}->{'IOPS'}->{'ul'}                          = "5000";
	$h->{$_}->{'IOPS'}->{'ll'}                          = "0";
	$h->{$_}->{'IOPS'}->{'zriopsavg'}->{'color'}                = $color_red;
	$h->{$_}->{'IOPS'}->{'zriopsavg'}->{'fill'}                 = "LINE";
	$h->{$_}->{'IOPS'}->{'zwiopsavg'}->{'color'}                = $color_blue;
	$h->{$_}->{'IOPS'}->{'zwiopsavg'}->{'fill'}                 = "LINE";

	$h->{$_}->{'THROUGHPUT'}->{'ul'}                    = "31457280";
	$h->{$_}->{'THROUGHPUT'}->{'ll'}                    = "0";
	$h->{$_}->{'THROUGHPUT'}->{'zrbwavgbytes'}->{'color'}       = $color_red;
	$h->{$_}->{'THROUGHPUT'}->{'zrbwavgbytes'}->{'fill'}        = "LINE";
	$h->{$_}->{'THROUGHPUT'}->{'zwbwavgbytes'}->{'color'}       = $color_blue;
	$h->{$_}->{'THROUGHPUT'}->{'zwbwavgbytes'}->{'fill'}        = "LINE";

	$h->{$_}->{'DISKUSAGE'}->{'ul'}                     = "100";
	$h->{$_}->{'DISKUSAGE'}->{'ll'}                     = "0";
	$h->{$_}->{'DISKUSAGE'}->{'zusedGB'}->{'color'}             = $color_brightgreen;
	$h->{$_}->{'DISKUSAGE'}->{'zusedGB'}->{'fill'}              = "LINE";
	$h->{$_}->{'DISKUSAGE'}->{'zavailGB'}->{'color'}            = $color_green;
	$h->{$_}->{'DISKUSAGE'}->{'zavailGB'}->{'fill'}             = "LINE";

	$h->{$_}->{'NETWORKTHROUGHPUT'}->{'ul'}             = "100000";
	$h->{$_}->{'NETWORKTHROUGHPUT'}->{'ll'}             = "0";
	$h->{$_}->{'NETWORKTHROUGHPUT'}->{'netrkbsavg'}->{'color'}  = $color_red;
	$h->{$_}->{'NETWORKTHROUGHPUT'}->{'netrkbsavg'}->{'fill'}   = "LINE";
	$h->{$_}->{'NETWORKTHROUGHPUT'}->{'netwkbsavg'}->{'color'}  = $color_blue;
	$h->{$_}->{'NETWORKTHROUGHPUT'}->{'netwkbsavg'}->{'fill'}   = "LINE";

	$h->{$_}->{'NETWORKUTIL'}->{'ul'}                   = "100";
	$h->{$_}->{'NETWORKUTIL'}->{'ll'}                   = "0";
	$h->{$_}->{'NETWORKUTIL'}->{'netnicutilavg'}->{'color'}     = $color_purple;
	$h->{$_}->{'NETWORKUTIL'}->{'netnicutilavg'}->{'fill'}      = "LINE";

	$h->{$_}->{'MEMORY'}->{'ul'}                        = "30000";
	$h->{$_}->{'MEMORY'}->{'ll'}                        = "0";
	$h->{$_}->{'MEMORY'}->{'vpiavg'}->{'color'}                 = $color_red;
	$h->{$_}->{'MEMORY'}->{'vpiavg'}->{'fill'}                  = "LINE";
	$h->{$_}->{'MEMORY'}->{'vpoavg'}->{'color'}                 = $color_blue;
	$h->{$_}->{'MEMORY'}->{'vpoavg'}->{'fill'}                  = "LINE";


} #End of WHILELISTFILE

#print Dumper($h);
#exit;



my $start = "end-$sd";
my $end = "now-$ed";
my $i=0;
#my $rrd_cmd1 = $rrd_cmd . " " . $outpath . "/" . $pstr ;
$rrd_cmd = "/sw/bin/rrdtool graph " .  $outpath ;
FOREACHHOST: foreach my $_host (keys(%{$h})) {
    my $rrdfile = $rrdhome . "/" . $pstr . "_" . $_host . ".rrd";
    FOREACHREPORT: foreach my $_report (keys(%{$h->{$_host}})) {
        $i=0;

        # Calculate upper and lower limits if defined:
        my $rrd_cmd1 = $rrd_cmd . "/" . $pstr . "_" . $_host . "_" .  $_report . ".png -a PNG --title \"$_host $_report\" -s $start -e $end ";
        if (defined($h->{$_host}->{$_report}->{'ul'})) {
            $rrd_cmd1 = $rrd_cmd1 . " -u " . $h->{$_host}->{$_report}->{'ul'};
        }
        if (defined($h->{$_host}->{$_report}->{'ll'})) {
            $rrd_cmd1 = $rrd_cmd1 . " -l " . $h->{$_host}->{$_report}->{'ll'};
        }

        # For every metric, add the DEF & LINE/AREA options:
        FOREACHMETRIC: foreach my $_metric (keys(%{$h->{$_host}->{$_report}})) {
            next FOREACHMETRIC if $_metric =~ m/ul/;
            next FOREACHMETRIC if $_metric =~ m/ll/;
            $rrd_cmd1 = $rrd_cmd1 . " DEF:" . $_metric . $i . "=" . $rrdfile . ":" . $_metric . ":AVERAGE:step=300:start=" . $start . ":end=" . $end;
            #print "$rrd_cmd1\n";
            $rrd_cmd1 = $rrd_cmd1 . " " . $h->{$_host}->{$_report}->{$_metric}->{'fill'} . ":";
            #print "bb\n";
            $rrd_cmd1 = $rrd_cmd1 . $_metric . $i . "\#" . $h->{$_host}->{$_report}->{$_metric}->{'color'} . ":\"" . $_host . " " . $_metric . "\"";
            $i++;
        } #End of FOREACHMETRIC

        if (defined($test)) {
            print $rrd_cmd1, "\n \n";
        } else {
            system($rrd_cmd1);
        }
    } #End of FOREACHREPORT
} #End of FOREACHHOST
exit;
closelog();
exit $rtn_code;
##############################
# POD
##############################
__END__


=head1 NAME

gprrd.pl - produces a batch of RRD graphs

=head1 SYNOPSIS

gprrd.pl --help
gprrd.pl [-H|--home /path/to/rrd] [--sd days] [--ed days] [-P|--pstr "string"] [-L|--list /path/to/listfile]

=head1 DESCRIPTION

Produces a batch of graphs from RRD files produced by mkrrd.pl

This script produces multiple graphs per host.   Each graph may contain multple, related metrics. 
The RRDs used to produce the graphs are created by the mkrrd.pl script.  It is assumed that the RRD binary is 
installed in /sw/bin.

Example:
gprrd.pl -P dm02 --sd=14 --ed 2 -L $HOME/lists/allHosts

=head1 OPTIONS

--help

--version

-H|--home /path/to/rrds <= full path to the location of the RRD database files.

--sd #   <= Number of days that will be substracted from the end date

--ed #   <= Number of days that will be subtracted from now

-P|--pstr  "string"  <= a string used to differentiate RRD databases

-L|--list /path/to/listfile <= Full path to a text file that contains hostnames

=head1 AUTHOR

Ferrum Vas <cancrixiii@gmail.com>


=head1 DATE

FIXMEDATE

=head1 TODO

*)


