#! /usr/bin/perl -w
###################################################################
# Oreon is developped with GPL Licence 2.0 
#
# GPL License: http://www.gnu.org/licenses/old-licenses/gpl-2.0.txt
#
# Developped by : Julien Mathis - Romain Le Merlus 
#
###################################################################
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
#    For information : contact@merethis.com
####################################################################
#
# Script init
#

use strict;
use Net::SNMP qw(:snmp);
use FindBin;
use lib "$FindBin::Bin";
use lib "/usr/lib/nagios/plugins";
use utils qw($TIMEOUT %ERRORS &print_revision &support);

if (eval "require centreon" ) {
    use centreon qw(get_parameters);
    use vars qw($VERSION %centreon);
    %centreon = get_parameters();
} else {
	print "Unable to load centreon perl module\n";
    exit $ERRORS{'UNKNOWN'};
}

use vars qw($PROGNAME);
use Getopt::Long;
use vars qw($opt_V $opt_h $opt_v $opt_C $opt_H $opt_c $opt_w $opt_D $snmp $opt_k $opt_u $opt_p @critical @warning $opt_l);

# Plugin var init

my($return_code);

$PROGNAME = "$0";
sub print_help ();
sub print_usage ();

Getopt::Long::Configure('bundling');
GetOptions
    ("h"   		=> \$opt_h, "help"         	=> \$opt_h,
     "u=s"   	=> \$opt_u, "username=s"    => \$opt_u,
     "p=s"   	=> \$opt_p, "password=s"    => \$opt_p,
     "k=s"   	=> \$opt_k, "key=s"         => \$opt_k,
     "V"   		=> \$opt_V, "version"      	=> \$opt_V,
     "v=s" 		=> \$opt_v, "snmp=s"       	=> \$opt_v,
     "C=s" 		=> \$opt_C, "community=s"  	=> \$opt_C,
     "w=s" 		=> \$opt_w, "warning=s"  	=> \$opt_w,
     "c=s" 		=> \$opt_c, "critical=s"  	=> \$opt_c,
     "H=s" 		=> \$opt_H, "hostname=s"   	=> \$opt_H, 
     "l"		=> \$opt_l);

if ($opt_V) {
    print_revision($PROGNAME,'$Revision: 1.2 $');
    exit $ERRORS{'OK'};
}

if ($opt_h) {
    print_help();
    exit $ERRORS{'OK'};
}

if (!$opt_H) {
	print_usage();
	exit $ERRORS{'OK'};
}

$opt_l = 0 if (!defined($opt_l));

my $snmp = "1";
$snmp = $opt_v if ($opt_v && $opt_v =~ /^[0-9]$/);

$opt_c = 95 if (!defined($opt_c) || !$opt_c);
$opt_w = 90 if (!defined($opt_w) || !$opt_w);

if ($snmp eq "3") {
	if (!$opt_u) {
		print "Option -u (--username) is required for snmpV3\n";
		exit $ERRORS{'UNKNOWN'};
	}
	if (!$opt_p && !$opt_k) {
		print "Option -k (--key) or -p (--password) is required for snmpV3\n";
		exit $ERRORS{'UNKNOWN'};
	} elsif ($opt_p && $opt_k) {
		print "Only option -k (--key) or -p (--password) is needed for snmpV3\n";
		exit $ERRORS{'UNKNOWN'};
	}
}

$opt_C = "public" if (!$opt_C);

my $name = $0;
$name =~ s/\.pl.*//g;

# Plugin snmp requests

my ($session, $error);
if ($snmp eq "1" || $snmp eq "2") {
	($session, $error) = Net::SNMP->session(-hostname => $opt_H, -community => $opt_C, -version => $snmp);
	if (!defined($session)) {
	    print("UNKNOWN: SNMP 1 or 2 Session : $error\n");
	    exit $ERRORS{'UNKNOWN'};
	}
} elsif ($opt_k) {
    ($session, $error) = Net::SNMP->session(-hostname => $opt_H, -version => $snmp, -username => $opt_u, -authkey => $opt_k);
	if (!defined($session)) {
	    print("UNKNOWN: SNMP Session : $error\n");
	    exit $ERRORS{'UNKNOWN'};
	}
} elsif ($opt_p) {
    ($session, $error) = Net::SNMP->session(-hostname => $opt_H, -version => $snmp,  -username => $opt_u, -authpassword => $opt_p);
	if (!defined($session)) {
	    print("UNKNOWN: SNMP Session : $error\n");
	    exit $ERRORS{'UNKNOWN'};
	}
}

sub get_netsnmp_version ($){
	my $sess = $_[0];
    my $OID_VERSION = "1.3.6.1.2.1.25.6.3.1.2";
    my $result = $sess->get_table(Baseoid => $OID_VERSION);
    if (!defined($result)) {
    	printf("ERROR when getting CPU percentage use values : ProcessorLoad Table : %s.\n", $session->error);
        $session->close;
        exit $ERRORS{'UNKNOWN'};
    }
    while ( my ($key, $value) = each(%$result) ) {
    	if ($value =~ m/net-snmp-5.3.*/) {
        	return "NetSNMP-5.3"
        }
    }
	return "Other";
}

my $OID_CPU = "";
my $snmpver = get_netsnmp_version($session);
if ( "$snmpver" eq "NetSNMP-5.3" ) {
	$OID_CPU = ".1.3.6.1.4.1.2021.11.9";
} else {
	$OID_CPU = ".1.3.6.1.2.1.25.3.3.1.2";
}


# Get all datas
my $result = $session->get_table(Baseoid => $OID_CPU);
if (!defined($result)) {
    printf("ERROR when getting CPU percentage use values : ProcessorLoad Table : %s.\n", $session->error);
    $session->close;
    exit $ERRORS{'UNKNOWN'};
}

# Get all values and computes average cpu.
my $cpu = 0;
my $i = 0;
my @cpulist;
foreach my $key ( oid_lex_sort(keys %$result)) {
    my @oid_list = split (/\./,$key);
    my $index = pop (@oid_list);
    $cpulist[$i] = $$result{$key};
	$cpu += $$result{$key};
	$i++;
}
undef($result);

$cpu /= $i;

# Plugin return code
my $status = "OK";
if ($cpu >= $opt_c) {
    $status = "CRITICAL";
} elsif ($cpu >= $opt_w) {
    $status = "WARNING";
}

my $str = "CPU utilization percentage : ".$cpu."%|avg=".$cpu."%";
if ($opt_l == 0) {
    for ($i = 0; defined($cpulist[$i]); $i++){
		$str .= " cpu$i=".$cpulist[$i]."%";
    }
}
print $str."\n";
undef($str);
exit $ERRORS{$status};

sub print_usage () {
    print "\nUsage:\n";
    print "$PROGNAME\n";
    print "This Plugin is design for return CPU percent on windows Serveurs (1 min Average)\n";
    print "\n";
    print "   -H (--hostname)   Hostname to query - (required)\n";
    print "   -C (--community)  SNMP read community (defaults to public,\n";
    print "   -c (--critical)   Three critical tresholds (defaults : 95)\n";
    print "   -w (--warning)    Three warning tresholds (defaults : 90)\n";
    print "   -v (--snmp_version)  1 for SNMP v1 (default)\n";
    print "                        2 for SNMP v2c\n";
    print "   -k (--key)        snmp V3 key\n";
    print "   -p (--password)   snmp V3 password\n";
    print "   -u (--username)   snmp v3 username \n";
    print "   -V (--version)    Plugin version\n";
    print "   -h (--help)       usage help\n";
}

sub print_help () {
    print "##############################################\n";
    print "#    Copyright (c) 2004-2009 Merethis        #\n";
    print "#    Bugs to http://trac.centreon.com/       #\n";
    print "##############################################\n";
    print_usage();
    print "\n";
}