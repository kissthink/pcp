#
# Copyright (c) 2009 Aconex.  All Rights Reserved.
# Copyright (c) 1998 Silicon Graphics, Inc.  All Rights Reserved.
#
# This program is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the
# Free Software Foundation; either version 2 of the License, or (at your
# option) any later version.
#
# This program is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
# or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
# for more details.
#
use strict;
use warnings;
use PCP::PMDA;
use DBI;

my $database = 'DBI:oracle:oracle';
my $username = 'dbmonitor';
my $password = 'dbmonitor';

my $sid = 'master';	# TODO
my $domain = 32;	# TODO

# Configuration files for overriding the above settings
for my $file (	'/etc/pcpdbi.conf',	# system defaults (lowest priority)
		pmda_config('PCP_PMDAS_DIR') . '/oracle/oracle.conf',
		'./oracle.conf' ) {	# current directory (high priority)
    eval `cat $file` unless ! -f $file;
}

use vars qw( $pmda %status %variables @processes );
use vars qw( @latch_instances @file_instances @rollback_instances );
use vars qw( @reqdist_instances @rowcache_instances @session_instances );
use vars qw( @cacheobj_instances @sysevents_instances );

my $latch_indom		= 0;
my $file_indom		= 1;
my $rollback_indom	= 2;
my $reqdist_indom	= 3;
my $rowcache_indom	= 4;
my $session_indom	= 5;
my $cacheobj_indom	= 6;
my $sysevents_indom	= 7;
my $libcache_indom	= 8;
my $waitstat_indom	= 9;

my @objcache_instances = (
    'INDEX', 'TABLE', 'CLUSTER', 'VIEW', 'SET', 'SYNONYM', 'SEQUENCE',
    'PROCEDURE', 'FUNCTION', 'PACKAGE', 'PACKAGE_BODY', 'TRIGGER', 'CLASS',
    'OBJECT', 'USER', 'DBLINK', 'NON-EXISTENT', 'NOT_LOADED', 'OTHER' );

my $CL_LICENSE		= 0;
my $CL_SYSSTAT		= 1;
my $CL_LATCH		= 2;
my $CL_FILESTAT		= 3;
my $CL_ROLLSTAT		= 4;
my $CL_REQDIST		= 5;
my $CL_BACKUP		= 6;
my $CL_ROWCACHE		= 7;
my $CL_SESSTAT		= 8;
my $CL_OBJCACHE		= 9;
my $CL_SYSEVENT		= 10;
my $CL_VERSION		= 11;
my $CL_LIBCACHE		= 12;
my $CL_WAITSTAT		= 13;

use vars qw( $dbh %events );
use vars qw( $indom_events $fetch_events $indom_backup $fetch_backup );
use vars qw( $indom_file $fetch_file $indom_latch $fetch_latch );
use vars qw( $indom_library $fetch_library $fetch_objcache $indom_reqdist );
use vars qw( $fetch_reqdist $indom_rollback $fetch_rollback $indom_rowcache );
use vars qw( $indom_session $fetch_session $indom_statname $fetch_statname );
use vars qw( $indom_sysevent $fetch_sysevent $fetch_sysstat $fetch_version );
use vars qw( $indom_waitstat $fetch_waitstat $fetch_rowcache );

sub oracle_connection_setup
{
    # $pmda->log("oracle_connection_setup\n");

    if (!defined($dbh)) {
	$dbh = DBI->connect($database, $username, $password);
	if (defined($dbh)) {
	    $pmda->log("Oracle connection established\n");
	    $indom_events = $dbh->prepare(
			'SELECT event#,name FROM v$event_name');
	    $fetch_events = $dbh->prepare(
			'SELECT event, total_waits, total_timeouts,
				time_waited, average_wait
			 FROM v$system_event');
	    $indom_backup = $dbh->prepare(
			'SELECT file# FROM v$backup');
	    $fetch_backup = $dbh->prepare(
			'SELECT file#, status FROM v$backup');
	    $indom_file = $dbh->prepare(
			'SELECT file#, name FROM v$datafile');
	    $fetch_file = $dbh->prepare(
			'SELECT file#, phyrds, phywrts, phyblkrd,
				       phyblkwrt, readtim, writetim
			 FROM v$filestat');
	    $indom_latch = $dbh->prepare(
			'SELECT latch#, name FROM v$latch');
	    $fetch_latch = $dbh->prepare(
			'SELECT latch#, gets, misses, sleeps,
				immediate_gets, immediate_misses,
				waiters_woken, waits_holding_latch, spin_gets
			 FROM v$latch');
	    $indom_library = $dbh->prepare(
			'SELECT namespace FROM v$librarycache');
	    $fetch_library = $dbh->prepare(
			'SELECT namespace, gets, gethits, gethitratio, pins,
				pinhits, pinhitratio, reloads, invalidations
			 FROM v$librarycache');
	    # objcache indom is a static array
	    $fetch_objcache = $dbh->prepare(
			'SELECT type, sharable_mem, loads, locks, pins
			 FROM v$db_object_cache');
	    $indom_reqdist = $dbh->prepare(
			'SELECT bucket FROM v$reqdist');
	    $fetch_reqdist = $dbh->prepare(
			'SELECT bucket, count FROM v$reqdist');
	    $indom_rollback = $dbh->prepare(
			'SELECT usn, name FROM v$rollname');
	    $fetch_rollback = $dbh->prepare(
			'SELECT usn, rssize, writes, xacts,
				gets, waits, hwmsize, shrinks, wraps,
				extends, aveshrink, aveactive
			 FROM v$rollstat');
	    $indom_rowcache = $dbh->prepare(
			'SELECT cache#, subordinate#, parameter
			 FROM v$rowcache');
	    $fetch_rowcache = $dbh->prepare(
			'SELECT cache#, subordinate#, count, gets,
				getmisses, scans, scanmisses
			 FROM v$rowcache');
	    $indom_session = $dbh->prepare(
			'SELECT sid FROM v$session');
	    $fetch_session = $dbh->prepare(
			'SELECT sid, statistic#, value FROM v$sesstat');
	    $indom_statname = $dbh->prepare(
			'SELECT statistic#, name FROM v$statname');
	    $fetch_statname = $dbh->prepare(
			'SELECT statistic#, name FROM v$statname');
	    $indom_sysevent = $dbh->prepare(
			'SELECT event#,name FROM v$event_name');
	    $fetch_sysevent = $dbh->prepare(
			'SELECT event, total_waits, total_timeouts,
				time_waited, average_wait
			 FROM v$system_event');
	    $fetch_sysstat = $dbh->prepare(
			'SELECT statistic#, value FROM v$sysstat');
	    $fetch_version = $dbh->prepare(
			'SELECT DISTINCT banner INTO :pc_version
			 FROM v$version WHERE banner LIKE \'Oracle%\'');
	    $indom_waitstat = $dbh->prepare(
			'SELECT class FROM v$waitstat');
	    $fetch_waitstat = $dbh->prepare(
			'SELECT class, count, time FROM v$waitstat');
	}
    }
}

sub oracle_events_refresh
{
    # $pmda->log("oracle_events_refresh\n");

    %events = ();	# clear any previous contents
    if (defined($dbh)) {
	$fetch_events->execute();
	my $result = $fetch_events->fetchall_arrayref();
	for my $i (0 .. $#{$result}) {
	    $events{$result->[$i][0]} = $result->[$i][1];
	}
    }
}

sub oracle_refresh
{
    my ($cluster) = @_;

    # $pmda->log("oracle_refresh $cluster\n");
    # if ($cluster == 0)	{ oracle_latch_refresh; }
    # elsif ($cluster == 1)	{ oracle_file_refresh; }
    # elsif ($cluster == 2)	{ oracle_rollback_refresh; }
    # elsif ($cluster == 3)	{ oracle_rollback_refresh; }
    # elsif ($cluster == 4)	{ oracle_reqdist_refresh; }
    # elsif ($cluster == 5)	{ oracle_rowcache_refresh; }
    # elsif ($cluster == 6)	{ oracle_cacheobj_refresh; }
    # elsif ($cluster == 7)	{ oracle_sysevents_refresh; }
}

sub oracle_fetch_callback
{
    my ($cluster, $item, $inst) = @_;

    # $pmda->log("oracle_fetch_callback $metric_name $cluster:$item ($inst)\n");
    # TODO ...

    return (PM_ERR_PMID, 0);
}


$pmda = PCP::PMDA->new("oracle", $domain);


## block contention stats from v$waitstat

$pmda->add_metric(pmda_pmid($CL_WAITSTAT,0), PM_TYPE_U32, $waitstat_indom,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.waitstat.count",
	'Number of waits for each block class',
'The number of waits for each class of block.  This value is obtained
from the COUNT column of the V$WAITSTAT view.');

$pmda->add_metric(pmda_pmid($CL_WAITSTAT,1), PM_TYPE_U32, $waitstat_indom,
	PM_SEM_COUNTER, pmda_units(0,1,0,0,PM_TIME_MSEC,0),
	"oracle.$sid.waitstat.time",
	'Sum of all wait times for each block class',
'The sum of all wait times for each block class.  This value is obtained
from the TIME column of the V$WAITSTAT view.');


## version data from the v$version view

$pmda->add_metric(pmda_pmid($CL_VERSION,0), PM_TYPE_STRING, PM_INDOM_NULL,
	PM_SEM_DISCRETE, pmda_units(0,0,0,0,0,0),
	"oracle.$sid.version",
	'ORACLE component name and version number', '');


## statistics from v$system_event

$pmda->add_metric(pmda_pmid($CL_SYSEVENT,0), PM_TYPE_U32, $sysevents_indom,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.event.waits",
	'Number of waits for various system events',
'The total number of waits for various system events.  This value is
obtained from the TOTAL_WAITS column of the V$SYSTEM_EVENT view.');

$pmda->add_metric(pmda_pmid($CL_SYSEVENT,1), PM_TYPE_U32, $sysevents_indom,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.event.timeouts",
	'Number of timeouts for various system events',
'The total number of timeouts for various system events.  This value is
obtained from the TOTAL_TIMEOUTS column of the V$SYSTEM_EVENT view.');

$pmda->add_metric(pmda_pmid($CL_SYSEVENT,2), PM_TYPE_U32, $sysevents_indom,
	PM_SEM_COUNTER, pmda_units(0,1,0,0,PM_TIME_MSEC,0),
	"oracle.$sid.event.time_waited",
	'Total time waited for various system events',
'The total amount of time waited for various system events.  This value
is obtained from the TIME_WAITED column of the V$SYSTEM_EVENT view and
converted to units of milliseconds.');

$pmda->add_metric(pmda_pmid($CL_SYSEVENT,3), PM_TYPE_FLOAT, $sysevents_indom,
	PM_SEM_INSTANT, pmda_units(0,1,0,0,PM_TIME_MSEC,0),
	"oracle.$sid.event.average_wait",
	'Average time waited for various system events',
'The average time waited for various system events.  This value is
obtained from the AVERAGE_WAIT column of the V$SYSTEM_EVENT view
and converted to units of milliseconds.');


## session statistics from v$sesstat and v$session

$pmda->add_metric(pmda_pmid(0,0), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.all.logons", 'Total cumulative logons',
'The "logons cumulative" statistic from the V$SYSSTAT view.  This is the
total number of logons since the instance started.');

$pmda->add_metric(pmda_pmid(0,1), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_INSTANT, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.all.curlogons", 'Total current logons',
'The "logons current" statistic from the V$SYSSTAT view.  This is the
total number of current logons.');

$pmda->add_metric(pmda_pmid(0,2), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.all.opencurs", 'Total cumulative opened cursors',
'The "opened cursors cumulative" statistic from the V$SYSSTAT view.
This is the total number of cursors opened since the instance started.');

$pmda->add_metric(pmda_pmid(0,3), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_INSTANT, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.all.curopencurs", 'Total current open cursors',
'The "opened cursors current" statistic from the V$SYSSTAT view.  This
is the total number of current open cursors.');

$pmda->add_metric(pmda_pmid(0,4), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.all.ucommits", 'Total user commits',
'The "user commits" statistic from the V$SYSSTAT view.  When a user
commits a transaction, the redo generated that reflects the changes
made to database blocks must be written to disk.  Commits often
represent the closest thing to a user transaction rate.');

$pmda->add_metric(pmda_pmid(0,5), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.all.urollbacks", 'Total user rollbacks',
'The "user rollbacks" statistic from the V$SYSSTAT view.  This statistic
stores the number of times users manually issue the ROLLBACK statement
or an error occurs during users\' transactions.');

$pmda->add_metric(pmda_pmid(0,6), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.all.ucalls", 'Total user calls',
'The "user calls" statistic from the V$SYSSTAT view.  ORACLE allocates
resources (Call State Objects) to keep track of relevant user call data
structures every time you log in, parse or execute.  When determining
activity, the ratio of user calls to RPI calls, gives you an indication
of how much internal work gets generated as a result of the type of
requests the user is sending to ORACLE.');

$pmda->add_metric(pmda_pmid(0,7), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.all.recursecalls", 'Total recursive calls',
'The "recursive calls" statistic from the V$SYSSTAT view.  ORACLE
maintains tables used for internal processing.  When ORACLE needs to
make a change to these tables, it internally generates an SQL
statement.  These internal SQL statements generate recursive calls.');

$pmda->add_metric(pmda_pmid(0,8), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,1,0,0,PM_TIME_MSEC,0),
	"oracle.$sid.all.recursecpu", 'Total recursive cpu usage',
'The "recursive cpu usage" statistic from the V$SYSSTAT view.  The total
CPU time used by non-user calls (recursive calls).  Subtract this value
from oracle.<inst>.all.secpu to determine how much CPU time was used
by the user calls.  Units are milliseconds of CPU time.');

$pmda->add_metric(pmda_pmid(0,9), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.all.selreads", 'Total session logical reads',
'The "session logical reads" statistic from the V$SYSSTAT view.  This
statistic is basically the sum of oracle.<inst>.all.dbbgets and
oracle.<inst>.all.consgets.  Refer to the help text for these
individual metrics for more information.');

$pmda->add_metric(pmda_pmid(0,10), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_INSTANT, pmda_units(1,0,0,PM_SPACE_BYTE,0,0),
	"oracle.$sid.all.seprocspace", 'Total session stored procedure space',
'The "session stored procedure space" statistic from the V$SYSSTAT
view.  This metric shows the amount of memory that this session is
using for stored procedures.');

$pmda->add_metric(pmda_pmid(0,11), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,1,0,0,PM_TIME_MSEC,0),
	"oracle.$sid.all.cpucall", 'CPU used when call started',
'The "CPU used when call started" statistic from the V$SYSSTAT view.
This is the session CPU when current call started.  Units are
milliseconds of CPU time.');

$pmda->add_metric(pmda_pmid(0,12), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,1,0,0,PM_TIME_MSEC,0),
	"oracle.$sid.all.secpu", 'Total CPU used by this session',
'The "CPU used by this session" statistic from the V$SYSSTAT view.  This
is the amount of CPU time used by a session between when a user call
started and ended.  Units for the exported metric are milliseconds, but
ORACLE uses an internal resolution of tens of milliseconds and some
user calls can complete within 10 milliseconds, resulting in the start
and end user-call times being the same.  In this case, zero
milliseconds are added to the statistic.');

$pmda->add_metric(pmda_pmid(0,13), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,1,0,0,PM_TIME_SEC,0),
	"oracle.$sid.all.secontime", 'Session connect time',
'The "session connect time" statistic from the V$SYSSTAT view.
Wall clock time of when session logon occured.  Units are seconds
since the epoch.');

$pmda->add_metric(pmda_pmid(0,14), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_INSTANT, pmda_units(0,1,0,0,PM_TIME_SEC,0),
	"oracle.$sid.all.procidle", 'Total process last non-idle time',
'The "process last non-idle time" statistic from the V$SYSSTAT view.
This is the last time this process was not idle.  Units are seconds
since the epoch.');

$pmda->add_metric(pmda_pmid(0,15), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_INSTANT, pmda_units(1,0,0,PM_SPACE_BYTE,0,0),
	"oracle.$sid.all.semem", 'Session UGA memory',
'The "session UGA memory" statistic from the V$SYSSTAT view.  This
shows the current session UGA (User Global Area) memory size.');

$pmda->add_metric(pmda_pmid(0,16), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_DISCRETE, pmda_units(1,0,0,PM_SPACE_BYTE,0,0),
	"oracle.$sid.all.maxsemem", 'Maximum session UGA memory',
'The "session UGA memory max" statistic from the V$SYSSTAT view.  This
shows the maximum session UGA (User Global Area) memory size.');

$pmda->add_metric(pmda_pmid(0,17), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.all.msgxmit", 'Total messages sent',
'The "messages sent" statistic from the V$SYSSTAT view.  This is the
total number of messages sent between ORACLE processes.  A message is
sent when one ORACLE process wants to post another to perform some
action.');

$pmda->add_metric(pmda_pmid(0,18), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.all.msgrecv", 'Total messages received',
'The "messages received" statistic from the V$SYSSTAT view.  This is the
total number of messages received.  A message is sent when one ORACLE
process wants to post another to perform some action.');

$pmda->add_metric(pmda_pmid(0,19), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.all.bgtimeouts", 'Total background timeouts',
'The "background timeouts" statistic from the V$SYSSTAT view.  This is
a count of the times where a background process has set an alarm for
itself and the alarm has timed out rather than the background process
being posted by another process to do some work.');

$pmda->add_metric(pmda_pmid(0,20), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_INSTANT, pmda_units(1,0,0,PM_SPACE_BYTE,0,0),
	"oracle.$sid.all.sepgamem", 'Session PGA memory',
'The "session PGA memory" statistic from the V$SYSSTAT view.  This
shows the current session PGA (Process Global Area) memory size.');

$pmda->add_metric(pmda_pmid(0,21), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_DISCRETE, pmda_units(1,0,0,PM_SPACE_BYTE,0,0),
	"oracle.$sid.all.semaxpgamem", 'Maximum session PGA memory',
'The "session PGA memory max" statistic from the V$SYSSTAT view.  This
shows the maximum session PGA (Process Global Area) memory size.');

$pmda->add_metric(pmda_pmid(0,22), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.all.enqueue.timeouts", 'Total enqueue timeouts',
'The "enqueue timeouts" statistic from the V$SYSSTAT view.  This is the
total number of enqueue operations (get and convert) that timed out
before they could complete.');

$pmda->add_metric(pmda_pmid(0,23), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.all.enqueue.waits", 'Total enqueue waits',
'The "enqueue waits" statistic from the V$SYSSTAT view.  This is the
total number of waits that happened during an enqueue convert or get
because the enqueue could not be immediately granted.');

$pmda->add_metric(pmda_pmid(0,24), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.all.enqueue.deadlocks", 'Total enqueue deadlocks',
'The "enqueue deadlocks" statistic from the V$SYSSTAT view.  This is
the total number of enqueue deadlocks between different sessions.');

$pmda->add_metric(pmda_pmid(0,25), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.all.enqueue.requests", 'Total enqueue requests',
'The "enqueue requests" statistic from the V$SYSSTAT view.  This is
the total number of enqueue gets.');

$pmda->add_metric(pmda_pmid(0,26), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.all.enqueue.conversions", 'Total enqueue conversions',
'The "enqueue conversions" statistic from the V$SYSSTAT view.  This is
the total number of enqueue converts.');

$pmda->add_metric(pmda_pmid(0,27), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.all.enqueue.releases", 'Total enqueue releases',
'The "enqueue releases" statistic from the V$SYSSTAT view.  This is
the total number of enqueue releases.');

$pmda->add_metric(pmda_pmid(0,28), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.all.globlock.gets", 'Total global lock gets (sync)',
'The "global lock gets (sync)" statistic from the V$SYSSTAT view.  This
is the total number of synchronous global lock gets.');

$pmda->add_metric(pmda_pmid(0,29), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.all.globlock.agets", 'Total global lock gets (async)',
'The "global lock gets (async)" statistic from the V$SYSSTAT view.
This is the total number of asynchronous global lock gets.');

$pmda->add_metric(pmda_pmid(0,30), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,1,0,0,PM_TIME_MSEC,0),
	"oracle.$sid.all.globlock.gettime", 'Total global lock get time',
'The "global lock get time" statistic from the V$SYSSTAT view.  This is
the total elapsed time of all synchronous global lock gets.');

$pmda->add_metric(pmda_pmid(0,31), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.all.globlock.cvts", 'Total global lock converts (sync)',
'The "global lock converts (sync)" statistic from the V$SYSSTAT view.
This is the total number of synchronous global lock converts.');

$pmda->add_metric(pmda_pmid(0,32), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.all.globlock.acvts", 'Total global lock converts (async)',
'The "global lock converts (async)" statistic from the V$SYSSTAT view.
This is the total number of asynchronous global lock converts.');

$pmda->add_metric(pmda_pmid(0,33), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,1,0,0,PM_TIME_MSEC,0),
	"oracle.$sid.all.globlock.cvttime", 'Total global lock convert time',
'The "global lock convert time" statistic from the V$SYSSTAT view.
This is the total elapsed time of all synchronous global lock converts.');

$pmda->add_metric(pmda_pmid(0,34), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.all.globlock.rels", 'Total global lock releases (sync)',
'The "global lock releases (sync)" statistic from the V$SYSSTAT view.
This is the total number of synchronous global lock releases.');

$pmda->add_metric(pmda_pmid(0,35), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.all.globlock.arels", 'Total global lock releases (async)',
'The "global lock releases (async)" statistic from the V$SYSSTAT view.
This is the total number of asynchronous global lock releases.');

$pmda->add_metric(pmda_pmid(0,36), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,1,0,0,PM_TIME_MSEC,0),
	"oracle.$sid.all.globlock.reltime", 'Total global lock release time',
'The "global lock release time" statistic from the V$SYSSTAT view.
This is the elapsed time of all synchronous global lock releases.');

$pmda->add_metric(pmda_pmid(0,37), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.all.dbbgets", 'Total db block gets',
'The "db block gets" statistic from the V$SYSSTAT view.  This tracks
the number of blocks obtained in CURRENT mode.');

$pmda->add_metric(pmda_pmid(0,38), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.all.consgets", 'Total consistent gets',
'The "consistent gets" statistic from the V$SYSSTAT view.  This is the
number of times a consistent read was requested for a block.  Also see
the help text for oracle.<inst>.all.conschanges.');

$pmda->add_metric(pmda_pmid(0,39), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.all.preads", 'Total physical reads',
'The "physical reads" statistic from the V$SYSSTAT view.  This is the
number of I/O requests to the operating system to retrieve a database
block from the disk subsystem.  This is a buffer cache miss.
Logical reads = oracle.<inst>.all.consgets + oracle.<inst>.all.dbbgets.
Logical reads and physical reads are used to calculate the buffer hit
ratio.');

$pmda->add_metric(pmda_pmid(0,40), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.all.pwrites", 'Total physical writes',
'The "physical writes" statistic from the V$SYSSTAT view.  This is the
number of I/O requests to the operating system to write a database
block to the disk subsystem.  The bulk of the writes are performed
either by DBWR or LGWR.');

$pmda->add_metric(pmda_pmid(0,41), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.all.wreqs", 'Total write requests',
'The "write requests" statistic from the V$SYSSTAT view.  This is the
number of times DBWR has flushed sets of dirty buffers to disk.');

$pmda->add_metric(pmda_pmid(0,42), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,0,0,0,0,0),
	"oracle.$sid.all.dirtyqlen", 'Total summed dirty queue length',
'The "summed dirty queue length" statistic from the V$SYSSTAT view.
This is the sum of the dirty LRU queue length after every write
request.
Divide by the write requests (oracle.<inst>.all.wreqs) to get the
average queue length after write completion.  For more information see
the help text associated with oracle.<inst>.all.wreqs.');

$pmda->add_metric(pmda_pmid(0,43), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.all.dbbchanges", 'Total db block changes',
'The "db block changes" statistic from the V$SYSSTAT view.  This metric
is closely related to "consistent changes"
(oracle.<inst>.all.conschanges) and counts the total number of
changes made to all blocks in the SGA that were part of an update or
delete operation.  These are the changes that are generating redo log
entries and hence will be permanent changes to the database if the
transaction is committed.
This metric is a rough indication of total database work and indicates
(possibly on a per-transaction level) the rate at which buffers are
being dirtied.');

$pmda->add_metric(pmda_pmid(0,44), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,1,0,0,PM_TIME_MSEC,0),
	"oracle.$sid.all.chwrtime", 'Total change write time',
'The "change write time" statistic from the V$SYSSTAT view.  This is
the elapsed time for redo write for changes made to CURRENT blocks.');

$pmda->add_metric(pmda_pmid(0,45), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.all.conschanges", 'Total consistent changes',
'The "consistent changes" statistic from the V$SYSSTAT view.  This is
the number of times a database block has applied rollback entries to
perform a consistent read on the block.');

$pmda->add_metric(pmda_pmid(0,46), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.all.redo.syncwr", 'Total redo sync writes',
'The "redo sync writes" statistic from the V$SYSSTAT view.  Usually,
redo that is generated and copied into the log buffer need not be
flushed out to disk immediately.  The log buffer is a circular buffer
that LGWR periodically flushes.  This metric is incremented when
changes being applied must be written out to disk due to commit.');

$pmda->add_metric(pmda_pmid(0,47), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,1,0,0,PM_TIME_MSEC,0),
	"oracle.$sid.all.redo.synctime", 'Total redo sync time',
'The "redo sync time" statistic from the V$SYSSTAT view.  This is the
elapsed time of all redo sync writes (oracle.<inst>.all.redo.syncwr).');

$pmda->add_metric(pmda_pmid(0,48), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.all.exdeadlocks", 'Total exchange deadlocks',
'The "exchange deadlocks" statistic from the V$SYSSTAT view.  This is
the number of times that a process detected a potential deadlock when
exchanging two buffers and raised an internal, restartable error.
Index scans are currently the only operations which perform exchanges.');

$pmda->add_metric(pmda_pmid(0,49), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.all.buffer.freereqs", 'Total free buffer requested',
'The "free buffer requested" statistic from the V$SYSSTAT view.  This is
the number of times a reusable buffer or a free buffer was requested to
create or load a block.');

$pmda->add_metric(pmda_pmid(0,50), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.all.buffer.dirtyinsp", 'Total dirty buffers inspected',
'The "dirty buffers inspected" statistic from the V$SYSSTAT view.
This is the number of dirty buffers found by the foreground while
the foreground is looking for a buffer to reuse.');

$pmda->add_metric(pmda_pmid(0,51), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.all.buffer.freeinsp", 'Total free buffer inspected',
'The "free buffer inspected" statistic from the V$SYSSTAT view.  This is
the number of buffers skipped over from the end of an LRU queue in
order to find a reusable buffer.  The difference between this metric
and the oracle.<inst>.all.buffer.dirtyinsp metric is the number of
buffers that could not be used because they were either busy, needed to
be written after rapid aging out, or they have a user, a waiter, or are
being read/written.  Refer to the oracle.<inst>.all.buffer.dirtyinsp
help text also.');

$pmda->add_metric(pmda_pmid(0,52), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.all.dbwr.timeouts", 'Total DBWR timeouts',
'The "DBWR timeouts" statistic from the V$SYSSTAT view.  This is the
number of times that the DBWR has been idle since the last timeout.
These are the times that the DBWR looked for buffers to idle write.');

$pmda->add_metric(pmda_pmid(0,53), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.all.dbwr.mkfreereqs", 'Total DBWR make free requests',
'The "DBWR make free requests" statistic from the V$SYSSTAT view.
This is the number of messages received requesting DBWR to make
some more free buffers for the LRU.');

$pmda->add_metric(pmda_pmid(0,54), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.all.dbwr.freebuffnd", 'Total DBWR free buffers found',
'The "DBWR free buffers found" statistic from the V$SYSSTAT view.
This is the number of buffers that DBWR found to be clean when it
was requested to make free buffers.  Divide this by
oracle.<inst>.all.dbwr.mkfreereqs to find the average number of
reusable buffers at the end of each LRU.');

$pmda->add_metric(pmda_pmid(0,55), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.all.dbwr.lruscans", 'Total DBWR lru scans',
'The "DBWR lru scans" statistic from the V$SYSSTAT view.  This is the
number of times that DBWR does a scan of the LRU queue looking for
buffers to write.  This includes times when the scan is to fill a batch
being written for another purpose such as a checkpoint.  This metric\'s
value is always greater than oracle.<inst>.all.dbwr.mkfreereqs.');

$pmda->add_metric(pmda_pmid(0,56), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.all.dbwr.sumscandepth", 'Total DBWR summed scan depth',
'The "DBWR summed scan depth" statistic from the V$SYSSTAT view.  The
current scan depth (number of buffers scanned by DBWR) is added to this
metric every time DBWR scans the LRU for dirty buffers.  Divide by
oracle.<inst>.all.dbwr.lruscans to find the average scan depth.');

$pmda->add_metric(pmda_pmid(0,57), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.all.dbwr.bufsscanned", 'Total DBWR buffers scanned',
'The "DBWR buffers scanned" statistic from the V$SYSSTAT view.
This is the total number of buffers looked at when scanning each
LRU set for dirty buffers to clean.  This count includes both dirty
and clean buffers.  Divide by oracle.<inst>.all.dbwr.lruscans to
find the average number of buffers scanned.');

$pmda->add_metric(pmda_pmid(0,58), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.all.dbwr.checkpoints", 'Total DBWR checkpoints',
'The "DBWR checkpoints" statistic from the V$SYSSTAT view.
This is the number of times the DBWR was asked to scan the cache
and write all blocks marked for a checkpoint.');

$pmda->add_metric(pmda_pmid(0,59), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.all.dbwr.xinstwrites", 'Total DBWR cross instance writes',
'The "DBWR cross instance writes" statistic from the V$SYSSTAT view.
This is the total number of blocks written for other instances so that
they can access the buffers.');

$pmda->add_metric(pmda_pmid(0,60), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.all.remote.instundowr",
	'Total remote instance undo writes',
'The "remote instance undo writes" statistic from the V$SYSSTAT view.
This is the number of times this instance performed a dirty undo write
so that another instance could read that data.');

$pmda->add_metric(pmda_pmid(0,61), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.all.remote.instundoreq",
	'Total remote instance undo requests',
'The "remote instance undo requests" statistic from the V$SYSSTAT view.
This is the number of times this instance requested undo from another
instance so it could be read CR.');

$pmda->add_metric(pmda_pmid(0,62), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.all.xinstcrrd", 'Total cross instance CR read',
'The "cross instance CR read" statistic from the V$SYSSTAT view.  This
is the number of times this instance made a cross instance call to
write a particular block due to timeout on an instance lock get.  The
call allowed the blocks to be read CR rather than CURRENT.');

$pmda->add_metric(pmda_pmid(0,63), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.all.kcmg.cscalls", 'Total calls to kcmgcs',
'The "calls to kcmgcs" statistic from the V$SYSSTAT view.  This is the
total number of calls to get the current System Commit Number (SCN).');

$pmda->add_metric(pmda_pmid(0,64), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.all.kcmg.rscalls", 'Total calls to kcmgrs',
'The "calls to kcmgrs" statistic from the V$SYSSTAT view.  This is the
total number of calls to get a recent System Commit Number (SCN).');

$pmda->add_metric(pmda_pmid(0,65), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.all.kcmg.ascalls", 'Total calls to kcmgas',
'The "calls to kcmgas" statistic from the V$SYSSTAT view.  This is the
total number of calls that Get and Advance the System Commit Number
(SCN).  Also used when getting a Batch of SCN numbers.');

$pmda->add_metric(pmda_pmid(0,66), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.all.nodlmscnsgets",
	'Total next scns gotten without going to DLM',
'The "next scns gotten without going to DLM" statistic from the
V$SYSSTAT view.  This is the number of SCNs (System Commit Numbers)
obtained without going to the DLM (Distributed Lock Manager).');

$pmda->add_metric(pmda_pmid(0,67), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.all.redo.entries", 'Total redo entries',
'The "redo entries" statistic from the V$SYSSTAT view.  This metric
is incremented each time redo entries are copied into the redo log
buffer.');

$pmda->add_metric(pmda_pmid(0,68), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(1,0,0,PM_SPACE_BYTE,0,0),
	"oracle.$sid.all.redo.size", 'Total redo size',
'The "redo size" statistic from the V$SYSSTAT view.
This is the number of bytes of redo generated.');

$pmda->add_metric(pmda_pmid(0,69), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.all.redo.entslin", 'Total redo entries linearized',
'The "redo entries linearized" statistic from the V$SYSSTAT view.  This
is the number of entries of size <= REDO_ENTRY_PREBUILD_THRESHOLD.
Building these entries increases CPU time but may increase concurrency.');

$pmda->add_metric(pmda_pmid(0,70), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.all.redo.bufallret",
	'Total redo buffer allocation retries',
'The "redo buffer allocation retries" statistic from the V$SYSSTAT
view.  This is the total number of retries necessary to allocate space
in the redo buffer.  Retries are needed because either the redo writer
has gotten behind, or because an event (such as log switch) is
occuring.');

$pmda->add_metric(pmda_pmid(0,71), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.all.redo.smallcpys", 'Total redo small copies',
'The "redo small copies" statistic from the V$SYSSTAT view.  This is the
total number of entries where size <= LOG_SMALL_ENTRY_MAX_SIZE.  These
entries are copied using the protection of the allocation latch,
eliminating the overhead of getting the copy latch. This is generally
only useful for multi-processor systems.');

$pmda->add_metric(pmda_pmid(0,72), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(1,0,0,PM_SPACE_BYTE,0,0),
	"oracle.$sid.all.redo.wastage", 'Total redo wastage',
'The "redo wastage" statistic from the V$SYSSTAT view.  This is the
number of bytes wasted because redo blocks needed to be written before
they are completely full.  Early writing may be needed to commit
transactions, to be able to write a database buffer or to switch logs.');

$pmda->add_metric(pmda_pmid(0,73), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,1,0,0,PM_TIME_MSEC,0),
	"oracle.$sid.all.redo.wrlatchtime", 'Total redo writer latching time',
'The "redo writer latching time" statistic from the V$SYSSTAT view.
This is the elapsed time needed by LGWR to obtain and release each copy
latch.  This is only used if the LOG_SIMULTANEOUS_COPIES initialization
parameter is greater than zero.');

$pmda->add_metric(pmda_pmid(0,74), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.all.redo.writes", 'Total redo writes',
'The "redo writes" statistic from the V$SYSSTAT view.
This is the total number of writes by LGWR to the redo log files.');

$pmda->add_metric(pmda_pmid(0,75), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.all.redo.bwrites", 'Total redo blocks written',
'The "redo blocks written" statistic from the V$SYSSTAT view.
This metric is not documented by ORACLE.');

$pmda->add_metric(pmda_pmid(0,76), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,1,0,0,PM_TIME_MSEC,0),
	"oracle.$sid.all.redo.wrtime", 'Total redo write time',
'The "redo write time" statistic from the V$SYSSTAT view.  This is the
total elapsed time of the write from the redo log buffer to the current
redo log file.');

$pmda->add_metric(pmda_pmid(0,77), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.all.redo.logspreqs", 'Total redo log space requests',
'The "redo log space requests" statistic from the V$SYSSTAT view.  The
active log file is full and ORACLE is waiting for disk space to be
allocated for the redo log entries.  Space is created by performing a
log switch.
Small log files in relation to the size of the SGA or the commit rate
of the work load can cause problems.  When the log switch occurs,
ORACLE must ensure that all committed dirty buffers are written to disk
before switching to a new log file.  If you have a large SGA full of
dirty buffers and small redo log files, a log switch must wait for DBWR
to write dirty buffers to disk before continuing.');

$pmda->add_metric(pmda_pmid(0,78), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,1,0,0,PM_TIME_MSEC,0),
	"oracle.$sid.all.redo.logspwaittime", 'Total redo log space wait time',
'The "redo log space wait time" statistic from the V$SYSSTAT view.  This
is the total elapsed time spent waiting for redo log space requests
(refer to the oracle.<inst>.all.redo.logspreqs metric).');

$pmda->add_metric(pmda_pmid(0,79), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.all.redo.logswintrs", 'Total redo log switch interrupts',
'The "redo log switch interrupts" statistic from the V$SYSSTAT view.
This is the number of times that another instance asked this instance
to advance to the next log file.');

$pmda->add_metric(pmda_pmid(0,80), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.all.redo.ordermarks", 'Total redo ordering marks',
'The "redo ordering marks" statistic from the V$SYSSTAT view.  This is
the number of times that an SCN (System Commit Number) had to be
allocated to force a redo record to have a higher SCN than a record
generated in another thread using the same block.');

$pmda->add_metric(pmda_pmid(0,81), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.all.hashlwgets", 'Total hash latch wait gets',
'The "hash latch wait gets" statistic from the V$SYSSTAT view.
This metric is not documented by ORACLE.');

$pmda->add_metric(pmda_pmid(0,82), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.all.bgchkpts.started",
	'Total background checkpoints started',
'The "background checkpoints started" statistic from the V$SYSSTAT
view.  This is the number of checkpoints started by the background.  It
can be larger than the number completed if a new checkpoint overrides
an incomplete checkpoint.  This only includes checkpoints of the
thread, not individual file checkpoints for operations such as offline
or begin backup.  This statistic does not include the checkpoints
performed in the foreground, such as ALTER SYSTEM CHECKPOINT LOCAL.');

$pmda->add_metric(pmda_pmid(0,83), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.all.bgchkpts.completed",
	'Total background checkpoints completed',
'The "background checkpoints completed" statistic from the V$SYSSTAT
view.  This is the number of checkpoints completed by the background.
This statistic is incremented when the background successfully advances
the thread checkpoint.');

$pmda->add_metric(pmda_pmid(0,84), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.all.tranlock.fgreqs",
	'Total transaction lock foreground requests',
'The "transaction lock foreground requests" statistic from the V$SYSSTAT
view.  For parallel server this is incremented on each call to ktugil()
"Kernel Transaction Get Instance Lock".  For single instance this has
no meaning.');

$pmda->add_metric(pmda_pmid(0,85), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,1,0,0,PM_TIME_MSEC,0),
	"oracle.$sid.all.tranlock.fgwaittime",
	'Total transaction lock foreground wait time',
'The "transaction lock foreground wait time" statistic from the
V$SYSSTAT view.  This is the total time spent waiting for a transaction
instance lock.');

$pmda->add_metric(pmda_pmid(0,86), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.all.tranlock.bggets",
	'Total transaction lock background gets',
'The "transaction lock background gets" statistic from the V$SYSSTAT
view.  For parallel server this is incremented on each call to ktuglb()
"Kernel Transaction Get lock in Background".');

$pmda->add_metric(pmda_pmid(0,87), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,1,0,0,PM_TIME_MSEC,0),
	"oracle.$sid.all.tranlock.bggettime",
	'Total transaction lock background get time',
'The "transaction lock background get time" statistic from the V$SYSSTAT
view.  Total time spent waiting for a transaction instance lock in
Background.');

$pmda->add_metric(pmda_pmid(0,88), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.all.table.shortscans", 'Total table scans (short tables)',
'The "table scans (short tables)" statistic from the V$SYSSTAT view.
Long (or conversely short) tables can be defined by optimizer hints
coming down into the row source access layer of ORACLE.  The table must
have the CACHE option set.');

$pmda->add_metric(pmda_pmid(0,89), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.all.table.longscans", 'Total table scans (long tables)',
'The "table scans (long tables)" statistic from the V$SYSSTAT view.
Long (or conversely short) tables can be defined as tables that do not
meet the short table criteria described in the help text for the
oracle.<inst>.all.table.shortscans metric.');

$pmda->add_metric(pmda_pmid(0,90), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.all.table.scanrows", 'Total table scan rows gotten',
'The "table scan rows gotten" statistic from the V$SYSSTAT view.  This
is collected during a scan operation, but instead of counting the
number of database blocks (see oracle.<inst>.all.table.scanblocks),
it counts the rows being processed.');

$pmda->add_metric(pmda_pmid(0,91), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.all.table.scanblocks", 'Total table scan blocks gotten',
'The "table scan blocks gotten" statistic from the V$SYSSTAT view.
During scanning operations, each row is retrieved sequentially by
ORACLE.  This metric is incremented for each block encountered during
the scan.
This informs you of the number of database blocks that you had to get
from the buffer cache for the purpose of scanning.  Compare the value
of this parameter to the value of oracle.<inst>.all.consgets
(consistent gets) to get a feel for how much of the consistent read
activity can be attributed to scanning.');

$pmda->add_metric(pmda_pmid(0,92), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.all.table.rowidfetches", 'Total table fetch by rowid',
'The "table fetch by rowid" statistic from the V$SYSSTAT view.  When
rows are fetched using a ROWID (usually from an index), each row
returned increments this counter.
This metric is an indication of row fetch operations being performed
with the aid of an index.  Because doing table scans usually indicates
either non-optimal queries or tables without indices, this metric
should increase as the above issues have been addressed in the
application.');

$pmda->add_metric(pmda_pmid(0,93), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.all.table.contfetches", 'Total table fetch continued row',
'The "table fetch continued row" statistic from the V$SYSSTAT view.
This metric is incremented when a row that spans more than one block is
encountered during a fetch.
Retrieving rows that span more than one block increases the logical I/O
by a factor that corresponds to the number of blocks that need to be
accessed.  Exporting and re-importing may eliminate this problem.  Also
take a closer look at the STORAGE parameters PCT_FREE and PCT_USED.
This problem cannot be fixed if rows are larger than database blocks
(for example, if the LONG datatype is used and the rows are extremely
large).');

$pmda->add_metric(pmda_pmid(0,94), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.all.clustkey.scans", 'Total cluster key scans',
'The "cluster key scans" statistic from the V$SYSSTAT view.
This is the number of cluster scans that were started.');

$pmda->add_metric(pmda_pmid(0,95), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.all.clustkey.scanblocks",
	'Total cluster key scan block gets',
'The "cluster key scan block gets" statistic from the V$SYSSTAT view.
This is the number of blocks obtained in a cluster scan.');

$pmda->add_metric(pmda_pmid(0,96), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,1,0,0,PM_TIME_MSEC,0),
	"oracle.$sid.all.sql.parsecpu", 'Total parse time cpu',
'The "parse time cpu" statistic from the V$SYSSTAT view.  This is the
total CPU time used for parsing (hard and soft parsing).  Units are
milliseconds of CPU time.');

$pmda->add_metric(pmda_pmid(0,97), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,1,0,0,PM_TIME_MSEC,0),
	"oracle.$sid.all.sql.parsereal", 'Total parse time elapsed',
'The "parse time elapsed" statistic from the V$SYSSTAT view.
This is the total elapsed time for parsing.  Subtracting
oracle.<inst>.all.sql.parsecpu from this metric gives the total
waiting time for parse resources.  Units are milliseconds.');

$pmda->add_metric(pmda_pmid(0,98), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.all.sql.parsed", 'Total parse count',
'The "parse count (total)" statistic from the V$SYSSTAT view.  This is
the total number of parse calls (hard and soft).  A soft parse is a
check to make sure that the permissions on the underlying objects have
not changed.');

$pmda->add_metric(pmda_pmid(0,99), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.all.sql.executed", 'Total execute count',
'The "execute count" statistic from the V$SYSSTAT view.
This is the total number of calls (user and recursive) that
execute SQL statements.');

$pmda->add_metric(pmda_pmid(0,100), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.all.sql.memsorts", 'Total sorts (memory)',
'The "sorts (memory)" statistic from the V$SYSSTAT view.  If the number
of disk writes is zero, then the sort was performed completely in
memory and this metric is incremented.
This is more an indication of sorting activity in the application
workload.  You cannot do much better than memory sorts, except for no
sorts at all.  Sorting is usually caused by selection criteria
specifications within table join SQL operations.');

$pmda->add_metric(pmda_pmid(0,101), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.all.sql.disksorts", 'Total sorts (disk)',
'The "sorts (disk)" statistic from the V$SYSSTAT view.  If the number
of disk writes is non-zero for a given sort operation, then this metric
is incremented.
Sorts that require I/O to disk are quite resource intensive.
Try increasing the size of the ORACLE initialization parameter
SORT_AREA_SIZE.');

$pmda->add_metric(pmda_pmid(0,102), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.all.sql.rowsorts", 'Total sorts (rows)',
'The "sorts (rows)" statistic from the V$SYSSTAT view.
This is the total number of rows sorted.');

$pmda->add_metric(pmda_pmid(0,103), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.all.sccachehits", 'Total session cursor cache hits',
'The "session cursor cache hits" statistic from the V$SYSSTAT view.
This is the count of the number of hits in the session cursor cache.
A hit means that the SQL statement did not have to be reparsed.
By subtracting this metric from oracle.<inst>.all.sql.parsed one can
determine the real number of parses that have been performed.');

$pmda->add_metric(pmda_pmid(0,104), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.all.cursauths", 'Total cursor authentications',
'The "cursor authentications" statistic from the V$SYSSTAT view.  This
is the total number of cursor authentications.  The number of times
that cursor privileges have been verified, either for a SELECT or
because privileges were revoked from an object, causing all users of
the cursor to be re-authenticated.');

$pmda->add_metric(pmda_pmid(0,105), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.all.recovery.breads", 'Total recovery blocks read',
'The "recovery blocks read" statistic from the V$SYSSTAT view.
This is the number of blocks read during recovery.');

$pmda->add_metric(pmda_pmid(0,106), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.all.recovery.areads", 'Total recovery array reads',
'The "recovery array reads" statistic from the V$SYSSTAT view.  This is
the number of reads performed during recovery.');

$pmda->add_metric(pmda_pmid(0,107), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,1,0,0,PM_TIME_MSEC,0),
	"oracle.$sid.all.recovery.areadtime", 'Total recovery array read time',
'The "recovery array read time" statistic from the V$SYSSTAT view.
This is the elapsed time of I/O while doing recovery.');

$pmda->add_metric(pmda_pmid(0,108), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.all.table.rowidrngscans",
	'Total table scans (rowid ranges)',
'The "table scans (rowid ranges)" statistic from the V$SYSSTAT view.
This is a count of the table scans with specified ROWID endpoints.
These scans are performed for Parallel Query.');

$pmda->add_metric(pmda_pmid(0,109), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.all.table.cachepartscans",
	'Total table scans (cache partitions)',
'The "table scans (cache partitions)" statistic from the V$SYSSTAT
view.  This is a count of range scans on tables that have the CACHE
option enabled.');

$pmda->add_metric(pmda_pmid(0,110), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.all.cr.createblk", 'Total CR blocks created',
'The "CR blocks created" statistic from the V$SYSSTAT view.
A buffer in the buffer cache was cloned.  The most common reason
for cloning is that the buffer is held in an incompatible mode.');

$pmda->add_metric(pmda_pmid(0,111), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.all.cr.convcurrblk",
	'Total Current blocks converted for CR',
'The "Current blocks converted for CR" statistic from the V$SYSSTAT
view.  A CURRENT buffer (shared or exclusive) is made CR before it can
be used.');

$pmda->add_metric(pmda_pmid(0,112), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.all.unnecprocclnscn",
	'Total Unnecessary process cleanup for SCN batching',
'The "Unnecessary process cleanup for SCN batching" statistic from the
V$SYSSTAT view.  This is the total number of times that the process
cleanup was performed unnecessarily because the session/process did not
get the next batched SCN (System Commit Number).  The next batched SCN
went to another session instead.');

$pmda->add_metric(pmda_pmid(0,113), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.all.consread.transtable.undo",
	'Total transaction tables consistent reads - undo records applied',
'The "transaction tables consistent reads - undo records applied"
statistic from the V$SYSSTAT view.  This is the number of UNDO records
applied to get CR images of data blocks.');

$pmda->add_metric(pmda_pmid(0,114), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.all.consread.transtable.rollback",
	'Total transaction tables consistent read rollbacks',
'The "transaction tables consistent read rollbacks" statistic from the
V$SYSSTAT view.  This is the total number of times transaction tables
are CR rolled back.');

$pmda->add_metric(pmda_pmid(0,115), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.all.datablkundo",
	'Total data blocks consistent reads - undo records applied',
'The "data blocks consistent reads - undo records applied" statistic
from the V$SYSSTAT view.  This is the total number of UNDO records
applied to get CR images of data blocks.');

$pmda->add_metric(pmda_pmid(0,116), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.all.noworkgets", 'Total no work - consistent read gets',
'The "no work - consistent read gets" statistic from the V$SYSSTAT
view.  This metric is not documented by ORACLE.');

$pmda->add_metric(pmda_pmid(0,117), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.all.consread.cleangets",
	'Total cleanouts only - consistent read gets',
'The "cleanouts only - consistent read gets" statistic from the
V$SYSSTAT view.  The number of times a CR get required a block
cleanout ONLY and no application of undo.');

$pmda->add_metric(pmda_pmid(0,118), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.all.consread.rollbackgets",
	'Total rollbacks only - consistent read gets',
'The "rollbacks only - consistent read gets" statistic from the
V$SYSSTAT view.  This is the total number of CR operations requiring
UNDO to be applied but no block cleanout.');

$pmda->add_metric(pmda_pmid(0,119), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.all.consread.cleanrollbackgets",
	'Total cleanouts and rollbacks - consistent read gets',
'The "cleanouts and rollbacks - consistent read gets" statistic from the
V$SYSSTAT view.  This is the total number of CR gets requiring BOTH
block cleanout and subsequent rollback to get to the required snapshot
time.');

$pmda->add_metric(pmda_pmid(0,120), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.all.rollbackchangeundo",
	'Total rollback changes - undo records applied',
'The "rollback changes - undo records applied" statistic from the
V$SYSSTAT view.  This is the total number of undo records applied to
blocks to rollback real changes.  Eg: as a result of a rollback command
and *NOT* in the process of getting a CR block image.
Eg:      commit;
         insert into mytab values (10);
         insert into mytab values (20);
         rollback;
should increase this statistic by 2 (assuming no recursive operations).');

$pmda->add_metric(pmda_pmid(0,121), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.all.transrollbacks", 'Total transaction rollbacks',
'The "transaction rollbacks" statistic from the V$SYSSTAT view.  This is
the actual transaction rollbacks that involve undoing real changes.
Contrast with oracle.<inst>.all.urollbacks ("user rollbacks") which
only indicates the number of ROLLBACK statements received.');

$pmda->add_metric(pmda_pmid(0,122), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.all.cleanout.immedcurr",
	'Total immediate (CURRENT) block cleanout applications',
'The "immediate (CURRENT) block cleanout applications" statistic from
the V$SYSSTAT view.  This metric is not documented by ORACLE.');

$pmda->add_metric(pmda_pmid(0,123), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.all.cleanout.immedcr",
	'Total immediate (CR) block cleanout applications',
'The "immediate (CR) block cleanout applications" statistic from the
V$SYSSTAT view.  This metric is not documented by ORACLE.');

$pmda->add_metric(pmda_pmid(0,124), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.all.cleanout.defercurr",
	'Total deferred (CURRENT) block cleanout applications',
'The "deferred (CURRENT) block cleanout applications" statistic from
the V$SYSSTAT view.  This is the number of times cleanout records are
deferred.  Deferred changes are piggybacked with real changes.');

$pmda->add_metric(pmda_pmid(0,125), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.all.table.dirreadscans", 'Total table scans (direct read)',
'The "table scans (direct read)" statistic from the V$SYSSTAT view.
This is a count of table scans performed with direct read (bypassing
the buffer cache).');

$pmda->add_metric(pmda_pmid(0,126), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.all.sccachecount", 'Total session cursor cache count',
'The "session cursor cache count" statistic from the V$SYSSTAT view.
This is the total number of cursors cached.  This is only incremented
if SESSION_CACHED_CURSORS is greater than zero.  This metric is the
most useful in V$SESSTAT.  If the value for this statistic is close to
the setting of the initialization parameter SESSION_CACHED_CURSORS, the
value of the initialization parameter should be increased.');

$pmda->add_metric(pmda_pmid(0,127), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.all.totalfileopens", 'Total file opens',
'The "total file opens" statistic from the V$SYSSTAT view.  This is the
total number of file opens being performed by the instance.  Each
process needs a number of files (control file, log file, database file)
in order to work against the database.');

$pmda->add_metric(pmda_pmid(0,128), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.all.cachereplaceopens",
	'Opens requiring cache replacement',
'The "opens requiring cache replacement" statistic from the V$SYSSTAT
view.  This is the total number of file opens that caused a current
file to be closed in the process file cache.');

$pmda->add_metric(pmda_pmid(0,129), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.all.replacedfileopens", 'Opens of replaced files',
'The "opens of replaced files" statistic from the V$SYSSTAT view.  This
is the total number of files that needed to be reopened because they
were no longer in the process file cache.');

$pmda->add_metric(pmda_pmid(0,130), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.all.commitcleanouts.total", 'Total commit cleanout calls',
'The "commit cleanouts" statistic from the V$SYSSTAT view.  This is the
number of times that the cleanout block at commit time function was
performed.');

$pmda->add_metric(pmda_pmid(0,131), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.all.commitcleanouts.completed",
	'Successful commit cleanouts',
'The "commit cleanouts successfully completed" metric from the V$SYSSTAT
view.  This is the number of times the cleanout block at commit time
function successfully completed.');

$pmda->add_metric(pmda_pmid(0,132), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.all.commitcleanouts.failures.writedisabled",
	'Commits when writes disabled',
'The "commit cleanout failures: write disabled" statistic from the
V$SYSSTAT view.  This is the number of times that a cleanout at commit
time was performed but the writes to the database had been temporarily
disabled.');

$pmda->add_metric(pmda_pmid(0,133), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.all.commitcleanouts.failures.hotbackup",
	'Commit attempts during hot backup',
'The "commit cleanout failures: hot backup in progress" statistic
from the V$SYSSTAT view.  This is the number of times that cleanout
at commit was attempted during hot backup.');

$pmda->add_metric(pmda_pmid(0,134), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.all.commitcleanouts.failures.bufferwrite",
	'Commits while buffer being written',
'The "commit cleanout failures: buffer being written" statistic from the
V$SYSSTAT view.  This is the number of times that a cleanout at commit
time was attempted but the buffer was being written at the time.');

$pmda->add_metric(pmda_pmid(0,135), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.all.commitcleanouts.failures.callbackfail",
	'Commit callback fails',
'The "commit cleanout failures: callback failure" statistic from the
V$SYSSTAT view.  This is the number of times that the cleanout callback
function returned FALSE (failed).');

$pmda->add_metric(pmda_pmid(0,136), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.all.commitcleanouts.failures.blocklost",
	'Commit fails due to lost block',
'The "commit cleanout failures: block lost" statistic from the V$SYSSTAT
view.  This is the number of times that a cleanout at commit was
attempted but could not find the correct block due to forced write,
replacement, or switch CURRENT.');

$pmda->add_metric(pmda_pmid(0,137), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.all.commitcleanouts.failures.cannotpin",
	'Commit fails due to block pinning',
'The "commit cleanout failures: cannot pin" statistic from the V$SYSSTAT
view.  This is the number of times that a commit cleanout was performed
but failed because the block could not be pinned.');

$pmda->add_metric(pmda_pmid(0,138), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.all.dbwr.skiphotwrites", 'Total DBWR hot writes skipped',
'The "DBWR skip hot writes" statistic from the V$SYSSTAT view.
This metric is not documented by ORACLE.');

$pmda->add_metric(pmda_pmid(0,139), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.all.dbwr.ckptbufwrites",
	'Total DBWR checkpoint buffers written',
'The "DBWR checkpoint buffers written" statistic from the V$SYSSTAT
view.  This is the number of times the DBWR was asked to scan the cache
and write all blocks marked for checkpoint.');

$pmda->add_metric(pmda_pmid(0,140), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.all.dbwr.transwrites",
	'Total DBWR transaction table writes',
'The "DBWR transaction table writes" statistic from the V$SYSSTAT view.
This metric is not documented by ORACLE.');

$pmda->add_metric(pmda_pmid(0,141), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.all.dbwr.undoblockwrites", 'Total DBWR undo block writes',
'The "DBWR undo block writes" statistic from the V$SYSSTAT view.
This metric is not documented by ORACLE.');

$pmda->add_metric(pmda_pmid(0,142), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.all.dbwr.ckptwritereq",
	'Total DBWR checkpoint write requests',
'The "DBWR checkpoint write requests" statistic from the V$SYSSTAT
view.  This is the number of times the DBWR was asked to scan the cache
and write all blocks.');

$pmda->add_metric(pmda_pmid(0,143), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.all.dbwr.incrckptwritereq",
	'Total DBWR incr checkpoint write requests',
'The "DBWR incr. ckpt. write requests" statistic from the V$SYSSTAT
view.  This metric is not documented by ORACLE.');

$pmda->add_metric(pmda_pmid(0,144), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.all.dbwr.revisitbuf",
	'Total DBWR being-written buffer revisits',
'The "DBWR revisited being-written buffer" statistic from the V$SYSSTAT
view.  This metric is not documented by ORACLE.');

$pmda->add_metric(pmda_pmid(0,145), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.all.dbwr.xinstflushcalls",
	'Total DBWR cross instance flush calls',
'The "DBWR Flush object cross instance calls" statistic from the
V$SYSSTAT view.  This is the number of times DBWR received a flush by
object number cross instance call (from a remote instance).  This
includes both checkpoint and invalidate object.');

$pmda->add_metric(pmda_pmid(0,146), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.all.dbwr.nodirtybufs",
	'DBWR flush calls finding no dirty buffers',
'The "DBWR Flush object call found no dirty buffers" statistic from the
V$SYSSTAT view.  DBWR didn\'t find any dirty buffers for an object that
was flushed from the cache.');

$pmda->add_metric(pmda_pmid(0,147), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.all.remote.instundoblockwr",
	'Remote instance undo block writes',
'The "remote instance undo block writes" statistic from the V$SYSSTAT
view.  This is the number of times this instance wrote a dirty undo
block so that another instance could read it.');

$pmda->add_metric(pmda_pmid(0,148), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.all.remote.instundoheaderwr",
	'Remote instance undo header writes',
'The "remote instance undo header writes" statistic from the V$SYSSTAT
view.  This is the number of times this instance wrote a dirty undo
header block so that another instance could read it.');

$pmda->add_metric(pmda_pmid(0,149), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.all.kcmgss_snapshotscn",
	'Total calls to get snapshot SCN: kcmgss',
'The "calls to get snapshot scn: kcmgss" statistic from the V$SYSSTAT
view.  This is the number of times a snap System Commit Number (SCN)
was allocated.  The SCN is allocated at the start of a transaction.');

$pmda->add_metric(pmda_pmid(0,150), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.all.kcmgss_batchwait", 'Total kcmgss waits for batching',
'The "kcmgss waited for batching" statistic from the V$SYSSTAT view.
This is the number of times the kernel waited on a snapshot System
Commit Number (SCN).');

$pmda->add_metric(pmda_pmid(0,151), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.all.kcmgss_nodlmscnread",
	'Total kcmgss SCN reads with using DLM',
'The "kcmgss read scn without going to DLM" statistic from the V$SYSSTAT
view.  This is the number of times the kernel casually confirmed the
System Commit Number (SCN) without using the Distributed Lock Manager
(DLM).');

$pmda->add_metric(pmda_pmid(0,152), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.all.kcmccs_currentscn",
	'Total kcmccs calls to get current SCN',
'The "kcmccs called get current scn" statistic from the V$SYSSTAT view.
This is the number of times the kernel got the CURRENT SCN (System
Commit Number) when there was a need to casually confirm the SCN.');

$pmda->add_metric(pmda_pmid(0,153), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.all.serializableaborts", 'Total serializable aborts',
'The "serializable aborts" statistic from the V$SYSSTAT view.  This is
the number of times a SQL statement in serializable isolation level had
to abort.');

$pmda->add_metric(pmda_pmid(0,154), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.all.globalcache.hashlatchwaits",
	'Global cache hash latch waits',
'The "global cache hash latch waits" statistic from the V$SYSSTAT view.
This is the number of times that the buffer cache hash chain latch
couldn\'t be acquired immediately, when processing a lock element.');

$pmda->add_metric(pmda_pmid(0,155), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.all.globalcache.freelistwaits",
	'Global cache freelist waits',
'The "global cache freelist waits" statistic from the V$SYSSTAT view.
This is the number of pings for free lock elements (when all release
locks are in use).');

$pmda->add_metric(pmda_pmid(0,156), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.all.globalcache.defers",
	'Global cache ping request defers',
'The "global cache defers" statistic from the V$SYSSTAT view.
This is the number of times a ping request was deferred until later.');

$pmda->add_metric(pmda_pmid(0,157), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.all.instrecoverdbfreeze",
	'Instance recovery database freezes',
'The "instance recovery database freeze count" statistic from the
V$SYSSTAT view.  This metric is not documented by ORACLE.');

$pmda->add_metric(pmda_pmid(0,158), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.all.commitscncached", 'Commit SCN cached',
'The "Commit SCN cached" statistic from the V$SYSSTAT view.  The System
Commit Number (SCN) is used to serialize time within a single instance,
and across all instances.  This lock resource caches the current value
of the SCN - the value is incremented in response to many database
events, but most notably COMMIT WORK.  Access to the SCN lock value to
get and store the SCN is batched on most cluster implementations, so
that every process that needs a new SCN gets one and stores a new value
back on one instance, before the SCN lock is released so that it may be
granted to another instance.  Processes get the SC lock once and then
use conversion operations to manipulate the lock value.');

$pmda->add_metric(pmda_pmid(0,159), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.all.cachedscnreferenced", 'Cached Commit SCN referenced',
'The "Cached Commit SCN referenced" statistic from the V$SYSSTAT view.
The SCN (System Commit Number), is generally a timing mechanism ORACLE
uses to guarantee ordering of transactions and to enable correct
recovery from failure.  They are used for guaranteeing
read-consistency, and checkpointing.');

$pmda->add_metric(pmda_pmid(0,160), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.all.hardparsed", 'Total number of hard parses performed',
'The "parse count (hard)" statistic from the V$SYSSTAT view.  This is
the total number of parse calls (real parses).  A hard parse means
allocating a workheap and other memory structures, and then building a
parse tree.  A hard parse is a very expensive operation in terms of
memory use.');

$pmda->add_metric(pmda_pmid(0,161), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(1,0,0,PM_SPACE_BYTE,0,0),
	"oracle.$sid.all.sqlnet.clientrecvs",
	'Total bytes from client via SQL*Net',
'The "bytes received via SQL*Net from client" statistic from the
V$SYSSTAT view.  This is the total number of bytes received from the
client over SQL*Net.');

$pmda->add_metric(pmda_pmid(0,162), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(1,0,0,PM_SPACE_BYTE,0,0),
	"oracle.$sid.all.sqlnet.clientsends",
	'Total bytes to client via SQL*Net',
'The "bytes sent via SQL*Net to client" statistic from the V$SYSSTAT
view.  This is the total number of bytes sent to the client over
SQL*Net.');

$pmda->add_metric(pmda_pmid(0,163), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.all.sqlnet.clientroundtrips",
	'Total client SQL*Net roundtrips',
'The "SQL*Net roundtrips to/from client" statistic from the V$SYSSTAT
view.  This is the total number of network messages sent to and
received from the client.');

$pmda->add_metric(pmda_pmid(0,164), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(1,0,0,PM_SPACE_BYTE,0,0),
	"oracle.$sid.all.sqlnet.dblinkrecvs",
	'Total bytes from dblink via SQL*Net',
'The "bytes received via SQL*Net from dblink" statistic from the
V$SYSSTAT view.  This is the total number of bytes received from
the database link over SQL*Net.');

$pmda->add_metric(pmda_pmid(0,165), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(1,0,0,PM_SPACE_BYTE,0,0),
	"oracle.$sid.all.sqlnet.dblinksends",
	'Total bytes to dblink via SQL*Net',
'The "bytes sent via SQL*Net to dblink" statistic from the V$SYSSTAT
view.  This is the total number of bytes sent over a database link.');

$pmda->add_metric(pmda_pmid(0,166), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.all.sqlnet.dblinkroundtrips",
	'Total dblink SQL*Net roundtrips',
'The "SQL*Net roundtrips to/from dblink" statistic from the V$SYSSTAT
view.  This is the total number of network messages sent to and
received from a database link.');

$pmda->add_metric(pmda_pmid(0,167), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.all.parallel.queries", 'Total queries parallelized',
'The "queries parallelized" statistic from the V$SYSSTAT view.  This is
the number of SELECT statements which have been parallelized.');

$pmda->add_metric(pmda_pmid(0,168), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.all.parallel.DMLstatements",
	'Total DML statements parallelized',
'The "DML statements parallelized" statistic from the V$SYSSTAT view.
This is the number of Data Manipulation Language (DML) statements which
have been parallelized.');

$pmda->add_metric(pmda_pmid(0,169), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.all.parallel.DDLstatements",
	'Total DDL statements parallelized',
'The "DDL statements parallelized" statistic from the V$SYSSTAT view.
This is the number of Data Definition Language (DDL) statements which
have been parallelized.');

$pmda->add_metric(pmda_pmid(0,170), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.all.PX.localsends", 'PX local messages sent',
'The "PX local messages sent" statistic from the V$SYSSTAT view.
This is the number of local messages sent for Parallel Execution.');

$pmda->add_metric(pmda_pmid(0,171), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.all.PX.localrecvs", 'PX local messages received',
'The "PX local messages recv\'d" statistic from the V$SYSSTAT view.
This is the number of local messages received for Parallel Execution.');

$pmda->add_metric(pmda_pmid(0,172), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.all.PX.remotesends", 'PX remote messages sent',
'The "PX remote messages sent" statistic from the V$SYSSTAT view.
This is the number of remote messages sent for Parallel Execution.');

$pmda->add_metric(pmda_pmid(0,173), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.all.PX.remoterecvs", 'PX remote messages received',
'The "PX remote messages recv\'d" statistic from the V$SYSSTAT view.
This is the number of remote messages received for Parallel Execution.');

$pmda->add_metric(pmda_pmid(0,174), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.all.buffer.pinned", 'Total pinned buffers',
'The "buffer is pinned count" statistic from the V$SYSSTAT view.
This metric is not documented by ORACLE.');

$pmda->add_metric(pmda_pmid(0,175), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.all.buffer.notpinned", 'Total not pinned buffers',
'The "buffer is not pinned count" statistic from the V$SYSSTAT view.
This metric is not documented by ORACLE.');

$pmda->add_metric(pmda_pmid(0,176), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.all.buffer.nonetopin", 'No buffer to keep pinned count',
'The "no buffer to keep pinned count" statistic from the V$SYSSTAT
view.  This metric is not documented by ORACLE.');

$pmda->add_metric(pmda_pmid(0,177), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,1,0,0,PM_TIME_MSEC,0),
	"oracle.$sid.all.OS.utime", 'OS User time used',
'The "OS User time used" statistic from the V$SYSSTAT view.
Units are milliseconds of CPU user time.');

$pmda->add_metric(pmda_pmid(0,178), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_COUNTER, pmda_units(0,1,0,0,PM_TIME_MSEC,0),
	"oracle.$sid.all.OS.stime", 'OS System time used',
'The "OS System time used" statistic from the V$SYSSTAT view.
Units are milliseconds of CPU system time.');


## row cache statistics from v$rowcache

$pmda->add_metric(pmda_pmid($CL_ROWCACHE,0), PM_TYPE_U32, $rowcache_indom,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.rowcache.count",
	'Number of entries in this data dictionary cache',
'The total number of data dictionary cache entries, broken down by data
type.  This is extracted from the COUNT column of the V$ROWCACHE view.');

$pmda->add_metric(pmda_pmid($CL_ROWCACHE,1), PM_TYPE_U32, $rowcache_indom,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.rowcache.gets",
	'Number of requests for cached information on data dictionary objects',
'The total number of valid data dictionary cache entries, broken down by
data type.  This is extracted from the GETS column of the V$ROWCACHE
view.');

$pmda->add_metric(pmda_pmid($CL_ROWCACHE,2), PM_TYPE_U32, $rowcache_indom,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.rowcache.getmisses",
	'Number of data requests resulting in cache misses',
'The total number of data dictionary requests that resulted in cache
misses, broken down by data type.  This is extracted from the GETMISSES
column of the V$ROWCACHE view.');

$pmda->add_metric(pmda_pmid($CL_ROWCACHE,3), PM_TYPE_U32, $rowcache_indom,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.rowcache.scans", 'Number of scan requests',
'The total number of data dictionary cache scans, broken down by data
type.  This is extracted from the SCANS column of the V$ROWCACHE view.');

$pmda->add_metric(pmda_pmid($CL_ROWCACHE,4), PM_TYPE_U32, $rowcache_indom,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.rowcache.scanmisses",
	'Number of data dictionary cache misses',
'The total number of times data dictionary cache scans failed to find
data in the cache, broken down by data type.  This is extracted from
the SCANMISSES column of the V$ROWCACHE view.');


## rollback I/O statistics from v$rollstat

$pmda->add_metric(pmda_pmid($CL_ROLLSTAT,0), PM_TYPE_U32, $rollback_indom,
	PM_SEM_INSTANT, pmda_units(1,0,0,PM_SPACE_BYTE,0,0),
	"oracle.$sid.rollback.rssize", 'Size of rollback segment',
'Size in bytes of the rollback segment.  This value is obtained from the
RSSIZE column in the V$ROLLSTAT view.');

$pmda->add_metric(pmda_pmid($CL_ROLLSTAT,1), PM_TYPE_U32, $rollback_indom,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.rollback.writes",
	'Number of bytes written to rollback segment',
'The total number of bytes written to rollback segment.  This value is
obtained from the WRITES column of the V$ROLLSTAT view.');

$pmda->add_metric(pmda_pmid($CL_ROLLSTAT,2), PM_TYPE_U32, $rollback_indom,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.rollback.xacts", 'Number of active transactions',
'The number of active transactions.  This value is obtained from the
XACTS column of the V$ROLLSTAT view.');

$pmda->add_metric(pmda_pmid($CL_ROLLSTAT,3), PM_TYPE_U32, $rollback_indom,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.rollback.gets",
	'Number of header gets for rollback segment',
'The number of header gets for the rollback segment.  This value is
obtained from the GETS column of the V$ROLLSTAT view.');

$pmda->add_metric(pmda_pmid($CL_ROLLSTAT,4), PM_TYPE_U32, $rollback_indom,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.rollback.waits",
	'Number of header waits for rollback segment',
'The number of header gets for the rollback segment.  This value is
obtained from the WAIT column of the V$ROLLSTAT view.');

$pmda->add_metric(pmda_pmid($CL_ROLLSTAT,5), PM_TYPE_U32, $rollback_indom,
	PM_SEM_INSTANT, pmda_units(1,0,0,PM_SPACE_BYTE,0,0),
	"oracle.$sid.rollback.hwmsize",
	'High water mark of rollback segment size',
'High water mark of rollback segment size.  This value is obtained from
the HWMSIZE column of the V$ROLLSTAT view.');

$pmda->add_metric(pmda_pmid($CL_ROLLSTAT,6), PM_TYPE_U32, $rollback_indom,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.rollback.shrinks",
	'Number of times rollback segment shrank',
'The number of times the size of the rollback segment decreased,
eliminating additional extents.  This value is obtained from the
SHRINKS column of the V$ROLLSTAT view.');

$pmda->add_metric(pmda_pmid($CL_ROLLSTAT,7), PM_TYPE_U32, $rollback_indom,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.rollback.wraps",
	'Number of times rollback segment wrapped',
'The number of times the rollback segment wrapped from one extent
to another.  This value is obtained from the WRAPS column of the
V$ROLLSTAT view.');

$pmda->add_metric(pmda_pmid($CL_ROLLSTAT,8), PM_TYPE_U32, $rollback_indom,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.rollback.extends",
	'Number of times rollback segment size extended',
'The number of times the size of the rollback segment grew to include
another extent.  This value is obtained from the EXTENDS column of the
V$ROLLSTAT view.');

$pmda->add_metric(pmda_pmid($CL_ROLLSTAT,9), PM_TYPE_U32, $rollback_indom,
	PM_SEM_INSTANT, pmda_units(1,0,0,PM_SPACE_BYTE,0,0),
	"oracle.$sid.rollback.avshrink", 'Average shrink size',
'Average of freed extent size for rollback segment.  This value is
obtained from the AVESHRINK column of the V$ROLLSTAT view.');

$pmda->add_metric(pmda_pmid($CL_ROLLSTAT,10), PM_TYPE_U32, $rollback_indom,
	PM_SEM_INSTANT, pmda_units(1,0,0,PM_SPACE_BYTE,0,0),
	"oracle.$sid.rollback.avactive",
	'Current size of active entents averaged over time',
'Current average size of extents with uncommitted transaction data.
This value is obtained from the AVEACTIVE column from the V$ROLLSTAT
view.');


## request time histogram from v$reqdist

$pmda->add_metric(pmda_pmid($CL_REQDIST,0), PM_TYPE_U32, $reqdist_indom,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.reqdist", 'Histogram of database operation request times',
'A histogram of database request times divided into twelve buckets (time
ranges).  This is extracted from the V$REQDIST table.
NOTE:
    The TIMED_STATISTICS database parameter must be TRUE or this metric
    will not return any values.');


## cache statistics from v$db_object_cache

$pmda->add_metric(pmda_pmid($CL_OBJCACHE,0), PM_TYPE_U32, $cacheobj_indom,
	PM_SEM_INSTANT, pmda_units(1,0,0,PM_SPACE_KBYTE,0,0),
	"oracle.$sid.objcache.sharemem",
	'Sharable memory usage in database cache pool by object types',
'The amount of sharable memory in the shared pool consumed by various
objects, divided into object types.  The valid object types are:
INDEX, TABLE, CLUSTER, VIEW, SET, SYNONYM, SEQUENCE, PROCEDURE,
FUNCTION, PACKAGE, PACKAGE BODY, TRIGGER, CLASS, OBJECT, USER, DBLINK,
NON_EXISTENT, NOT LOADED and OTHER.
The values for each of these object types are obtained from the
SHARABLE_MEM column of the V$DB_OBJECT_CACHE view.');

$pmda->add_metric(pmda_pmid($CL_OBJCACHE,1), PM_TYPE_U32, $cacheobj_indom,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.objcache.loads", 'Number of times object loaded',
'The number of times the object has been loaded.  This count also
increases when and object has been invalidated.  These values are
obtained from the LOADS column of the V$DB_OBJECT_CACHE view.');

$pmda->add_metric(pmda_pmid($CL_OBJCACHE,2), PM_TYPE_U32, $cacheobj_indom,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.objcache.locks",
	'Number of users currently locking this object',
'The number of users currently locking this object.  These values are
obtained from the LOCKS column of the V$DB_OBJECT_CACHE view.');

$pmda->add_metric(pmda_pmid($CL_OBJCACHE,3), PM_TYPE_U32, $cacheobj_indom,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.objcache.pins",
	'Number of users currently pinning this object',
'The number of users currently pinning this object.  These values are
obtained from the PINS column of the V$DB_OBJECT_CACHE view.');


## licence data from v$license

$pmda->add_metric(pmda_pmid($CL_LICENSE,0), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_INSTANT, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.license.maxsess",
	'Maximum number of concurrent user sessions',
'The maximum number of concurrent user sessions permitted for the
instance.  This value is obtained from the SESSIONS_MAX column of
the V$LICENSE view.');

$pmda->add_metric(
	pmda_pmid($CL_LICENSE,1), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_INSTANT, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.license.cursess",
	'Current number of concurrent user sessions',
'The current number of concurrent user sessions for the instance.
This value is obtained from the SESSIONS_CURRENT column of the
V$LICENSE view.');

$pmda->add_metric(
	pmda_pmid($CL_LICENSE,2), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_INSTANT, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.license.warnsess",
	'Warning limit for concurrent user sessions',
'The warning limit for concurrent user sessions for this instance.
This value is obtained from the SESSIONS_WARNING column of the
V$LICENSE view.');

$pmda->add_metric(
	pmda_pmid($CL_LICENSE,3), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_INSTANT, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.license.highsess",
	'Highest number of concurrent user sessions since instance started',
'The highest number of concurrent user sessions since the instance
started.  This value is obtained from the SESSIONS_HIGHWATER column of
the V$LICENSE view.');

$pmda->add_metric(pmda_pmid($CL_LICENSE,4), PM_TYPE_U32, PM_INDOM_NULL,
	PM_SEM_INSTANT, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.license.maxusers",
	'Maximum number of named users permitted',
'The maximum number of named users allowed for the database.  This value
is obtained from the USERS_MAX column of the V$LICENSE view.');


## statistics from v$librarycache

$pmda->add_metric(pmda_pmid($CL_LIBCACHE,0), PM_TYPE_U32, $libcache_indom,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.librarycache.gets",
	'Number of lock requests for each namespace object',
'The number of times a lock was requested for objects of this
namespace.  This value is obtained from the GETS column of the
V$LIBRARYCACHE view.');

$pmda->add_metric(pmda_pmid($CL_LIBCACHE,1), PM_TYPE_U32, $libcache_indom,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.librarycache.gethits",
	'Number of times objects handle found in memory',
'The number of times an object\'s handle was found in memory.  This value
is obtained from the GETHITS column of the V$LIBRARYCACHE view.');

$pmda->add_metric(pmda_pmid($CL_LIBCACHE,2), PM_TYPE_FLOAT, $libcache_indom,
	PM_SEM_INSTANT, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.librarycache.gethitratio",
	'Ratio of gethits to hits',
'The ratio of GETHITS to HITS.  This value is obtained from the
GETHITRATIO column of the V$LIBRARYCACHE view.');


$pmda->add_metric(pmda_pmid($CL_LIBCACHE,3), PM_TYPE_U32, $libcache_indom,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.librarycache.pins",
	'Number of times a pin was requested for each namespace object',
'The number of times a PIN was requested for each object of the library
cache namespace.  This value is obtained from the PINS column of the
V$LIBRARYCACHE view.');

$pmda->add_metric(pmda_pmid($CL_LIBCACHE,4), PM_TYPE_U32, $libcache_indom,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.librarycache.pinhits",
	'Number of times all metadata found in memory',
'The number of times that all of the meta data pieces of the library
object were found in memory.  This value is obtained from the PINHITS
column of the V$LIBRARYCACHE view.');

$pmda->add_metric(pmda_pmid($CL_LIBCACHE,5), PM_TYPE_FLOAT, $libcache_indom,
	PM_SEM_INSTANT, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.librarycache.pinhitratio", 'Ratio of pins to pinhits',
'The ratio of PINS to PINHITS.  This value is obtained from the
PINHITRATIO column of the V$LIBRARYCACHE view.');

$pmda->add_metric(pmda_pmid($CL_LIBCACHE,6), PM_TYPE_U32, $libcache_indom,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.librarycache.reloads", 'Number of disk reloads required',
'Any PIN of an object that is not the first PIN performed since the
object handle was created, and which requires loading the object from
the disk.  This value is obtained from the RELOADS column of the
V$LIBRARYCACHE view.');

$pmda->add_metric(pmda_pmid($CL_LIBCACHE,7), PM_TYPE_U32, $libcache_indom,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.librarycache.invalidations",
	'Invalidations due to dependent object modifications',
'The total number of times objects in the library cache namespace were
marked invalid due to a dependent object having been modified.  This
value is obtained from the INVALIDATIONS column of the V$LIBRARYCACHE
view.');


## latch statistics from v$latch

$pmda->add_metric(pmda_pmid($CL_LATCH,0), PM_TYPE_U32, $latch_indom,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.latch.gets",
	'Number of times obtained a wait',
'The number of times latch obtained a wait.  These values are obtained
from the GETS column of the V$LATCH view.');

$pmda->add_metric(pmda_pmid($CL_LATCH,1), PM_TYPE_U32, $latch_indom,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.latch.misses",
	'Number of times obtained a wait but failed on first try',
'The number of times obtained a wait but failed on the first try.  These
values are obtained from the MISSES column of the V$LATCH view.');

$pmda->add_metric(pmda_pmid($CL_LATCH,2), PM_TYPE_U32, $latch_indom,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.latch.sleeps",
	'Number of times slept when wanted a wait',
'The number of times slept when wanted a wait.  These values are
obtained from the SLEEPS column of the V$LATCH view.');

$pmda->add_metric(pmda_pmid($CL_LATCH,3), PM_TYPE_U32, $latch_indom,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.latch.imgets",
	'Number of times obtained without a wait',
'The number of times latch obtained without a wait.  These values are
obtained from the IMMEDIATE_GETS column of the V$LATCH view.');

$pmda->add_metric(pmda_pmid($CL_LATCH,4), PM_TYPE_U32, $latch_indom,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.latch.immisses",
	'Number of times failed to get latch without a wait',
'The number of times failed to get latch without a wait.  These values
are obtained from the IMMEDIATE_MISSES column of the V$LATCH view.');

$pmda->add_metric(pmda_pmid($CL_LATCH,5), PM_TYPE_U32, $latch_indom,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.latch.wakes",
	'Number of times a wait was awakened',
'The number of times a wait was awakened.  These values are obtained
from the WAITERS_WOKEN column of the V$LATCH view.');

$pmda->add_metric(pmda_pmid($CL_LATCH,6), PM_TYPE_U32, $latch_indom,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.latch.holds",
	'Number of waits while holding a different latch',
'The number of waits while holding a different latch.  These values are
obtained from the WAITS_HOLDING_LATCH column of the V$LATCH view.');

$pmda->add_metric(pmda_pmid($CL_LATCH,7), PM_TYPE_U32, $latch_indom,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.latch.spingets",
	'Gets that missed first try but succeeded on spin',
'Gets that missed first try but succeeded on spin.  These values are
obtained from the SPIN_GETS column of the V$LATCH view.');


## file backup status from v$backup

$pmda->add_metric(pmda_pmid($CL_BACKUP,0), PM_TYPE_U32, $file_indom,
	PM_SEM_INSTANT, pmda_units(0,0,0,0,0,0),
	"oracle.$sid.backup.status",
	'Backup status of online datafiles',
'The Backup status of online datafiles.  The status is encoded as an
ASCII character:
	not active      -  ( 45)
	active          +  ( 43)
	offline         o  (111)
	normal          n  (110)
	error           E  ( 69)
This value is extracted from the STATUS column of the V$BACKUP view.');


## file I/O statistics from v$filestat

$pmda->add_metric(pmda_pmid($CL_FILESTAT,0), PM_TYPE_U32, $file_indom,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.file.phyrds",
	'Physical reads from database files',
'The number of physical reads from each database file.  These values
are obtained from the PHYRDS column in the V$FILESTAT view.');

$pmda->add_metric(pmda_pmid($CL_FILESTAT,1), PM_TYPE_U32, $file_indom,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.file.phywrts",
	'Physical writes to database files',
'The number of times the DBWR process is required to write to each of
the database files.  These values are obtained from the PHYWRTS column
in the V$FILESTAT view.');

$pmda->add_metric(pmda_pmid($CL_FILESTAT,2), PM_TYPE_U32, $file_indom,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.file.phyblkrd",
	'Physical blocks read from database files',
'The number of physical blocks read from each database file.  These
values are obtained from the PHYBLKRDS column in the V$FILESTAT view.');

$pmda->add_metric(pmda_pmid($CL_FILESTAT,3), PM_TYPE_U32, $file_indom,
	PM_SEM_COUNTER, pmda_units(0,0,1,0,0,PM_COUNT_ONE),
	"oracle.$sid.file.phyblkwrt",
	'Physical blocks written to database files',
'The number of physical blocks written to each database file.  These
values are obtained from the PHYBLKWRT column in the V$FILESTAT view.');

$pmda->add_metric(pmda_pmid($CL_FILESTAT,4), PM_TYPE_U32, $file_indom,
	PM_SEM_COUNTER, pmda_units(0,0,0,0,0,0),
	"oracle.$sid.file.readtim",
	'Time spent reading from database files',
'The number of milliseconds spent doing reads if the TIMED_STATISTICS
database parameter is true.  If this parameter is false, then the
metric will have a value of zero.  This value is obtained from the
READTIM column of the V$FILESTAT view.');

$pmda->add_metric(pmda_pmid($CL_FILESTAT,5), PM_TYPE_U32, $file_indom,
	PM_SEM_COUNTER, pmda_units(0,0,0,0,0,0),
	"oracle.$sid.file.writetim",
	'Time spent writing to database files',
'The number of milliseconds spent doing writes if the TIMED_STATISTICS
database parameter is true.  If this parameter is false, then the
metric will have a value of zero.  This value is obtained from the
WRITETIM column of the V$FILESTAT view.');



$pmda->add_indom($latch_indom, \@latch_instances,
		'Instance domain "latch" from Oracle PMDA',
'The latches used by the RDBMS.  The latch instance domain does not
change.  Latches are simple, low-level serialization mechanisms which
protect access to structures in the system global area (SGA).');

$pmda->add_indom($file_indom, \@file_instances,
		'Instance domain "file" from Oracle PMDA',
'The collection of data files that make up the database.  This instance
domain may change during database operation as files are added to or
removed.');

$pmda->add_indom($rollback_indom, \@rollback_instances,
		'Instance domain "rollback" from Oracle PMDA',
'The collection of rollback segments for the database.  This instance
domain may change during database operation as segments are added to or
removed.');

$pmda->add_indom($reqdist_indom, \@reqdist_instances,
		'RDBMS Request Distribution from Oracle PMDA',
'Each instance is one of the buckets in the histogram of RDBMS request
service times.  The instances are named according to the longest
service time that will be inserted into its bucket.  The instance
domain does not change.');

$pmda->add_indom($rowcache_indom, \@rowcache_instances,
		'Instance domain "rowcache" from Oracle PMDA',
'Each instance is a type of data dictionary cache.  The names are
derived from the database parameters that define the number of entries
in the particular cache.  In some cases subordinate caches exist.
Names for such sub-caches are composed of the subordinate cache
parameter name prefixed with parent cache name with a "." as a
separator.  Each cache has an identifying number which appears in
parentheses after the textual portion of the cache name to resolve
naming ambiguities.  The rowcache instance domain does not change.');

$pmda->add_indom($session_indom, \@session_instances,
		'Instance domain "session" from Oracle PMDA',
'Each instance is a session to the Oracle database.  Sessions may come
and go rapidly.  The instance names correspond to the numeric Oracle
session identifiers.
NOTE:
    Oracle re-uses session identifiers.  If a session closes down, a
    subsequently created session may be given the closed sessions
    session identifier.  The cost of obtaining a unique, temporally
    consistent identifier for each session was deemed too high, so raw
    session identifiers are used.');

$pmda->add_indom($cacheobj_indom, \@cacheobj_instances,
		'Instance domain "cacheobj" from Oracle PMDA',
'The various types of objects in the database object cache.  This
includes such objects as indices, tables, procedures, packages, users
and dblink.  Any object types not recognized by the Oracle PMDA are
grouped together into a special instance named "other".  The instance
domain may change as various types of objects are bought into and
flushed out of the database object cache.');

$pmda->add_indom($sysevents_indom, \@sysevents_instances,
		'Instance domain "sysevents" from Oracle PMDA',
'The various system events which the database may wait on.  This
includes events such as interprocess communication, control file I/O,
log file I/O, timers.');

$pmda->set_fetch_callback(\&oracle_fetch_callback);
$pmda->set_fetch(\&oracle_connection_setup);
$pmda->set_refresh(\&oracle_refresh);
$pmda->run;

=pod

=head1 NAME

pmdaoracle - performance metrics domain agent for Oracle

=head1 DESCRIPTION

B<pmdaoracle> is a Performance Metrics Domain Agent (PMDA) that obtains
performance metrics from an Oracle database instance and makes them
available to users of the Performance Co-Pilot (PCP) monitor tools.

B<pmdaoracle> retrieves information from the database by querying the
dynamic performance (V$...) views.
Queries are performed only when metrics are requested from the PMDA to
minimize impact on the database.

B<pmdaoracle> monitors a single Oracle database instance.
If multiple database instances are to be monitored with PCP, there must
be a separate instance of the agent running on the same machine as the
database it monitors.

The Performance Metrics Collector Daemon, B<pmcd> launches B<pmdaoracle>;
it should not be executed directly.  See the installation section below
for instructions on how to configure and start the agent.

=head1 INSTALLATION

B<pmdaoracle> uses a configuration file from (in this order):

=over

=item * /etc/pcpdbi.conf

=item * $PCP_PMDAS_DIR/oracle/oracle.conf

=back

This file can contain overridden values (Perl code) for the settings
listed at the start of pmdaoracle.pl, namely:

=over

=item * database name (see DBI(3) for details)

=item * database user name

=item * database pass word

=back

Once this is setup, you can access the names and values for the
oracle performance metrics by doing the following as root:

	# cd $PCP_PMDAS_DIR/oracle
	# ./Install

If you want to undo the installation, do the following as root:

	# cd $PCP_PMDAS_DIR/oracle
	# ./Remove

B<pmdaoracle> is launched by pmcd(1) and should never be executed
directly.  The Install and Remove scripts notify pmcd(1) when
the agent is installed or removed.

=head1 FILES

=over

=item /etc/pcpdbi.conf

configuration file for all PCP database monitors

=item $PCP_PMDAS_DIR/oracle/oracle.conf

configuration file for B<pmdaoracle>

=item $PCP_PMDAS_DIR/oracle/Install

installation script for the B<pmdaoracle> agent

=item $PCP_PMDAS_DIR/oracle/Remove

undo installation script for the B<pmdaoracle> agent

=item $PCP_LOG_DIR/pmcd/oracle.log

default log file for error messages from B<pmdaoracle>

=back

=head1 SEE ALSO

pmcd(1), pmdadbping.pl(1) and DBI(3).