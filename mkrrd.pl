#!/usr/bin/perl -w
use strict;
use warnings;
use diagnostics;
use Data::Dumper;
use File::Basename;
use File::Find;
use Getopt::Long;
Getopt::Long::Configure('bundling');
use Pod::Usage;
use Sys::Hostname;
use Sys::Syslog qw(:DEFAULT setlogsock);
use POSIX;
use Time::Local;
#use List::Util;

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
my ($help, $man, $version, $verbose, $debug);
my ($rrdfilestr, $csvfile);
GetOptions (
    'help'          => \$help,
    'man'           => \$man,
    'version'       => \$version,
    'verbose'       => \$verbose,
    'debug'         => \$debug,
    'P|rrdfilestr=s'     => \$rrdfilestr,
    'csvfile=s'     => \$csvfile
       
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

unless(defined($csvfile)) {
    $csvfile = $HOME . "/rrd/ds/out.csv";
}


##############################
# Functions
##############################
sub yesterday {
	my $dayshift = shift;
	$dayshift = $dayshift * (-1);
	my $type = shift;
	my $oneday=86400*$dayshift;
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
	    } elsif ($type eq "0") {
            $yest=$epoch;
	    } else {
	        print "Please use a correct type format.\n";
	        pod2usage(2);
	    }
	} else {
       	 $yest=strftime("%m/%d/%Y",localtime($epoch));
	}
	return $yest;
} #End of sub yesterday

sub ts2epoch {
    my $_tsd = shift;
    my $_tst = shift;
    my $oneday = 86400;
    my ($_tmon,$_tday,$_tyr) = split(/\//,$_tsd);
    my ($_thr,$_tmin,$_tsec) = split(/:/,$_tst);

    #$_tsec = 0 unless(defined($_tsec));
    #$_tmin = 0 unless(defined($_tmin));
    #$_thr = 0 unless(defined($_thr));

    my $_epoch = timelocal($_tsec,$_tmin,$_thr,$_tday,$_tmon-1,$_tyr);

    return $_epoch;

}#Enf of sub ts2epoch


sub commifylist {
	(@_ == 0) ? ''  	:
	(@_ == 1) ? $_[0]	:
	(@_ == 2) ? join(",",@_):
	join(",", @_[0 .. ($#_-1)], "$_[-1]");
} #End of sub commifylist


##############################
# Main`
##############################
my $r;

#
# Sanity
#if (-e $rrdfile) {
#    print "file $rrdfile already exists.\n";
#    exit;
#}



#
# open the out.csv file & populate $r
#
open(CSVFILE,"$csvfile") or die "Can't open $csvfile:$!\n";
WHILECSVFILE: while (<CSVFILE>) {
    chomp;
    next WHILECSVFILE if m/^host/;
    s/ //g;
    my ($_host,$_date,$_time,$_cpuidle,$_cpucnt,$_load1,$_load5,$_load15,$_zriopsavg,$_zwiopsavg,$_zrbwavgbytes,$_zwbwavgbytes,$_zusedGB,$_zavailGB,$_netrkbsavg,$_netwkbsavg,$_netnicutilavg,$_vpiavg,$_vpoavg) = split(/,/,$_);
    my $_epochts = &ts2epoch($_date,$_time);
    #print "datestr>> ", $_date, " ", $_time, " epoch>> ", $_epochts, "\n";
    #print $_, "\n";
    $r->{$_host}->{$_epochts}->{'cpuidle'}=$_cpuidle;
    $r->{$_host}->{$_epochts}->{'cpucnt'}=$_cpucnt;
    $r->{$_host}->{$_epochts}->{'load1'}=$_load1;
    $r->{$_host}->{$_epochts}->{'load5'}=$_load5;
    $r->{$_host}->{$_epochts}->{'load15'}=$_load15;
    $r->{$_host}->{$_epochts}->{'zriopsavg'}=$_zriopsavg;
    $r->{$_host}->{$_epochts}->{'zwiopsavg'}=$_zwiopsavg;
    $r->{$_host}->{$_epochts}->{'zrbwavgbytes'}=$_zrbwavgbytes;
    $r->{$_host}->{$_epochts}->{'zwbwavgbytes'}=$_zwbwavgbytes;
    $r->{$_host}->{$_epochts}->{'zusedGB'}=$_zusedGB;
    $r->{$_host}->{$_epochts}->{'zavailGB'}=$_zavailGB;
    $r->{$_host}->{$_epochts}->{'netrkbsavg'}=$_netrkbsavg;
    $r->{$_host}->{$_epochts}->{'netwkbsavg'}=$_netwkbsavg;
    $r->{$_host}->{$_epochts}->{'netnicutilavg'}=$_netnicutilavg;
    $r->{$_host}->{$_epochts}->{'vpiavg'}=$_vpiavg;
    $r->{$_host}->{$_epochts}->{'vpoavg'}=$_vpoavg;

} #End of WHILECSFILE
close(CSVFILE);

#print Dumper($r);
#exit;

#
# Create the empty RRD:
#
my $y = &yesterday(-30,0);
my $rrdbin = "/sw/bin/rrdtool";
FOREACHHOST: foreach my $_h (sort(keys(%{$r}))) {
    my ($_hstr,$_dm1,$_dm2,$_dm3,$_dm4) = split(/\./,$_h);
	my $rrdfile = "/Users/bleak/rrd/" . $rrdfilestr . "_" . $_hstr . ".rrd";
    print ">>", $rrdfile, "\n\n";
    next FOREACHHOST if -e $rrdfile;
	my $r_cmd = $rrdbin . " create " . $rrdfile . " --start " . $y ;
	$r_cmd = $r_cmd . " --step 300 DS:cpuidle:GAUGE:600:0:100 ";
	$r_cmd = $r_cmd . " --step 300 DS:cpucnt:GAUGE:600:0:256 ";
	$r_cmd = $r_cmd . " --step 300 DS:load1:GAUGE:600:0:100 ";
	$r_cmd = $r_cmd . " --step 300 DS:load5:GAUGE:600:0:100 ";
	$r_cmd = $r_cmd . " --step 300 DS:load15:GAUGE:600:0:100 ";
	$r_cmd = $r_cmd . " --step 300 DS:zriopsavg:GAUGE:600:0:U ";
	$r_cmd = $r_cmd . " --step 300 DS:zwiopsavg:GAUGE:600:0:U ";
	$r_cmd = $r_cmd . " --step 300 DS:zrbwavgbytes:GAUGE:600:0:U ";
	$r_cmd = $r_cmd . " --step 300 DS:zwbwavgbytes:GAUGE:600:0:U ";
	$r_cmd = $r_cmd . " --step 300 DS:zusedGB:GAUGE:600:0:U ";
	$r_cmd = $r_cmd . " --step 300 DS:zavailGB:GAUGE:600:0:U ";
	$r_cmd = $r_cmd . " --step 300 DS:netrkbsavg:GAUGE:600:0:U ";
	$r_cmd = $r_cmd . " --step 300 DS:netwkbsavg:GAUGE:600:0:U ";
	$r_cmd = $r_cmd . " --step 300 DS:netnicutilavg:GAUGE:600:0:U ";
	$r_cmd = $r_cmd . " --step 300 DS:vpiavg:GAUGE:600:0:U ";
	$r_cmd = $r_cmd . " --step 300 DS:vpoavg:GAUGE:600:0:U ";
	$r_cmd = $r_cmd . " RRA:AVERAGE:0:1:12";   # <= last hour
	$r_cmd = $r_cmd . " RRA:AVERAGE:0:6:72";   # <= last six hours
	$r_cmd = $r_cmd . " RRA:AVERAGE:0:12:144";   # <= last 12 hours
	$r_cmd = $r_cmd . " RRA:AVERAGE:0:1:288";   # <= last day
	$r_cmd = $r_cmd . " RRA:AVERAGE:0:2:576";   # <= last 2 days
	$r_cmd = $r_cmd . " RRA:AVERAGE:0:7:576";   # <= last 7 days
	$r_cmd = $r_cmd . " RRA:AVERAGE:0:14:576";   # <= last 14 days
	$r_cmd = $r_cmd . " RRA:AVERAGE:0:30:576";   # <= last 30 days
	$r_cmd = $r_cmd . " RRA:AVERAGE:0:90:576";   # <= last 90 days (1 quarter)
	$r_cmd = $r_cmd . " RRA:AVERAGE:0:180:576";   # <= last 180 days (2 quarter2)
	$r_cmd = $r_cmd . " RRA:AVERAGE:0:360:576";   # <= last 360 days (1 year)
	$r_cmd = $r_cmd . " RRA:AVERAGE:0:720:576";   # <= last 720 days (2 years)
	$r_cmd = $r_cmd . " RRA:AVERAGE:0:1800:576";   # <= last 1800 days (5 years)
	system($r_cmd);
	# Make the RRD:
}#End of FOREACHHOST

#
# Update the RRD with data:
#
#my $i = 0;
#my $ru_cmd = $rrdbin . " update " . $rrdfile . " ";



#my $s = 1313528400;
#my $s = 1313614800;
#my $s = 1313539200;
#my $s = $y;
#my $ru_cmddata = " ";
#my $PDP = 100;
#until ($i == 100) {
#    $i++;
#    $s = $s + 300;
#    $PDP = $PDP + 1;
#    my $updatecmd = $ru_cmd . " " . $s . ":" . $PDP;
#    # Update the RRD with data
#    print ">> ", $updatecmd, "\n";
#    system($updatecmd);
#}
#$ru_cmd = $ru_cmd . $ru_cmddata;
#print Dumper($r);
#exit;
my $c=0;
FOREACHHOSTRU: foreach my $_host (sort(keys(%{$r}))) {
    #print "AA\n";
    foreach my $_epochts (sort(keys(%{$r->{$_host}}))) {
        my ($_hstr,$_dm1,$_dm2,$_dm3,$_dm4) = split(/\./,$_host);
        my $rrdcmd = $rrdbin . " update /Users/bleak/rrd/" . $rrdfilestr . "_" . $_hstr . ".rrd ";
#        $rrdcmd = $rrdcmd . " " . $_epochts . ":" . $r->{$_host}->{$_epochts}->{'cpuidle'};
#        $rrdcmd = $rrdcmd . " " . $_epochts . ":" . $r->{$_host}->{$_epochts}->{'cpucnt'};
#        $rrdcmd = $rrdcmd . " " . $_epochts . ":" . $r->{$_host}->{$_epochts}->{'load1'};
#        $rrdcmd = $rrdcmd . " " . $_epochts . ":" . $r->{$_host}->{$_epochts}->{'load5'};
#        $rrdcmd = $rrdcmd . " " . $_epochts . ":" . $r->{$_host}->{$_epochts}->{'load15'};
#        $rrdcmd = $rrdcmd . " " . $_epochts . ":" . $r->{$_host}->{$_epochts}->{'zriopsavg'};
#        $rrdcmd = $rrdcmd . " " . $_epochts . ":" . $r->{$_host}->{$_epochts}->{'zwiopsavg'};
#        $rrdcmd = $rrdcmd . " " . $_epochts . ":" . $r->{$_host}->{$_epochts}->{'zrbwavgbytes'};
#        $rrdcmd = $rrdcmd . " " . $_epochts . ":" . $r->{$_host}->{$_epochts}->{'zwbwavgbytes'};
#        $rrdcmd = $rrdcmd . " " . $_epochts . ":" . $r->{$_host}->{$_epochts}->{'zusedGB'};
#        $rrdcmd = $rrdcmd . " " . $_epochts . ":" . $r->{$_host}->{$_epochts}->{'zavailGB'};
#        $rrdcmd = $rrdcmd . " " . $_epochts . ":" . $r->{$_host}->{$_epochts}->{'netrkbsavg'};
#        $rrdcmd = $rrdcmd . " " . $_epochts . ":" . $r->{$_host}->{$_epochts}->{'netwkbsavg'};
#        $rrdcmd = $rrdcmd . " " . $_epochts . ":" . $r->{$_host}->{$_epochts}->{'netnicutilavg'};
#        $rrdcmd = $rrdcmd . " " . $_epochts . ":" . $r->{$_host}->{$_epochts}->{'vpiavg'};
#        $rrdcmd = $rrdcmd . " " . $_epochts . ":" . $r->{$_host}->{$_epochts}->{'vpoavg'};
       
        $rrdcmd = $rrdcmd . " " . $_epochts . ":" . $r->{$_host}->{$_epochts}->{'cpuidle'};
        $rrdcmd = $rrdcmd . ":" . $r->{$_host}->{$_epochts}->{'cpucnt'};
        $rrdcmd = $rrdcmd . ":" . $r->{$_host}->{$_epochts}->{'load1'};
        $rrdcmd = $rrdcmd . ":" . $r->{$_host}->{$_epochts}->{'load5'};
        $rrdcmd = $rrdcmd . ":" . $r->{$_host}->{$_epochts}->{'load15'};
        $rrdcmd = $rrdcmd . ":" . $r->{$_host}->{$_epochts}->{'zriopsavg'};
        $rrdcmd = $rrdcmd . ":" . $r->{$_host}->{$_epochts}->{'zwiopsavg'};
        $rrdcmd = $rrdcmd . ":" . $r->{$_host}->{$_epochts}->{'zrbwavgbytes'};
        $rrdcmd = $rrdcmd . ":" . $r->{$_host}->{$_epochts}->{'zwbwavgbytes'};
        $rrdcmd = $rrdcmd . ":" . $r->{$_host}->{$_epochts}->{'zusedGB'};
        $rrdcmd = $rrdcmd . ":" . $r->{$_host}->{$_epochts}->{'zavailGB'};
        $rrdcmd = $rrdcmd . ":" . $r->{$_host}->{$_epochts}->{'netrkbsavg'};
        $rrdcmd = $rrdcmd . ":" . $r->{$_host}->{$_epochts}->{'netwkbsavg'};
        $rrdcmd = $rrdcmd . ":" . $r->{$_host}->{$_epochts}->{'netnicutilavg'};
        $rrdcmd = $rrdcmd . ":" . $r->{$_host}->{$_epochts}->{'vpiavg'};
        $rrdcmd = $rrdcmd . ":" . $r->{$_host}->{$_epochts}->{'vpoavg'};
        print ">> $rrdcmd \n";
        #sleep(5);
        #$c++;print $c*".";print "\n";
        system($rrdcmd);

    }
} #End of FOREACHHOSTRU
#    $r->{$_host}->{$_epochts}->{'cpuidle'}=$_cpuidle;
#    $r->{$_host}->{$_epochts}->{'cpucnt'}=$_cpucnt;
#    $r->{$_host}->{$_epochts}->{'load1'}=$_load1;
#    $r->{$_host}->{$_epochts}->{'load5'}=$_load5;
#    $r->{$_host}->{$_epochts}->{'load15'}=$_load15;
#    $r->{$_host}->{$_epochts}->{'zriopsavg'}=$_zriopsavg;
#    $r->{$_host}->{$_epochts}->{'zwiopsavg'}=$_zwiopsavg;
#    $r->{$_host}->{$_epochts}->{'zrbwavgbytes'}=$_zrbwavgbytes;
#    $r->{$_host}->{$_epochts}->{'zwbwavgbytes'}=$_zwbwavgbytes;
#    $r->{$_host}->{$_epochts}->{'zusedGB'}=$_zusedGB;
#    $r->{$_host}->{$_epochts}->{'zavailGB'}=$_zavailGB;
#    $r->{$_host}->{$_epochts}->{'netrkbsavg'}=$_netrkbsavg;
#    $r->{$_host}->{$_epochts}->{'netwkbsavg'}=$_netwkbsavg;
#    $r->{$_host}->{$_epochts}->{'netnicutilavg'}=$_netnicutilavg;
#    $r->{$_host}->{$_epochts}->{'vpiavg'}=$_vpiavg;

#my $rf_cmd = $rrdbin . " fetch " . $rrdfile . " AVERAGE";
#print $ru_cmd, "\n";
#print $rf_cmd, "\n";


# Show some data:
#system($rf_cmd);



closelog();
exit $rtn_code;
##############################
# POD
##############################
__END__


=head1 NAME

mkrrd.pl - does something interesting

=head1 SYNOPSIS

mkrrd.pl --help

mkrrd.pl -P|--rrdfilestr="string" --csvfile=/path/to/file

=head1 DESCRIPTION

This script takes a single csv file as input and updates the CSV files into a set of RRD databases.
There will be one RRD file per host.

=head1 OPTIONS

--help

--version

-R|--rrdfilestr a string to differentiate the new files if needed.  <= required

--csvfile /path/to/csv_input_file

=head1 AUTHOR

Ferrum Vas <cancrixiii@gmail.com>


=head1 DATE

FIXMEDATE

=head1 TODO

*)


