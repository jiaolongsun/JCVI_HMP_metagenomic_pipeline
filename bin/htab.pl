#!/usr/local/bin/perl
##################################################################
# $Header: /usr/local/devel/microbial/src/RCS/htab.pl,v 1.3 2002/09/18 19:06:17 tanjad Exp tanjad $
##################################################################
#  Revision History:
#    $Log: htab.pl,v $
#
#    Revision 1.5  2009/04/21 jhoover
#    - use SQLite egad.db instead of Sybase egad database
#    - extended details included in htab results
#    - read rfam HMM details from table rfam instead of hmm2
#    - fully implemented -s (no databse) option
#    - added -d option to override the default SQLite egad database
#
#    Revision 1.4  2009/04/14 aklump
#    handle CLC HMMer output (actual changes are in hmm_lib)
#
#    Revision 1.3  2002/09/18 tanjad
#    minor modifications
#
#    Revision 1.3  2000/08/11 fyang
#    minor modifications
#
#    Revision 1.1  2000/05/13 fyang
#    minor modifications
#
#    Revision 1.2  2000/02/18 fyang
#    minor modifications
#
#    Revision 1.1  2000/02/11 fyang
#    Initial revision
#
##################################################################
{
use strict;
use DBI;
use Getopt::Std;
use Cwd 'realpath';
use File::Basename;

my $program = realpath($0);
my $htabDir = dirname($program);
our $defaultEgad = "$htabDir/egad.db";
require "$htabDir/hmm_lib.pl";

my $usage = <<_EOT_;
NAME
    htab.pl - parse output files generated by hmmsearch and hmmpfam, and 
              output btab-like table of results.

SYNOPSIS
    htab.pl [OPTION] <hmm_results_file >htab_results_file
	
	hmmsearch ... | htab.pl [OPTION] >htab_results_file 
    
    ls file_name | htab.pl -f [OPTION]


DESCRIPTION
    htab.pl parses HMM search results for HMMER.  It will parse the output 
    of a single search from STDIN and output tab-delimited data for each 
    hit to STDOUT. Multiple files may be processed using the -f option (see 
    below). During parsing, the size and cutoffs for each HMM is gathered 
    from the egad database. HMMER version 2.1.1 output is currently supported.

    -d <sqlite db> to override the default egad database.
    -f    a flag indicating that the input is a list of file names to be parsed.
          Each file is processed and the results are saved as "filename.htab"
          in the directory where the file is. 
    -h    a flag to print this help message
    -m    a flag for supporting output from multiple query sequences
    -s    a flag to skip database query
    -t    input a value for trusted_cutoff (for hmmsearch log, replace the value retrieved from db)
    -n    input a value for noise_cutoff   (for hmmsearch log, replace the value retrieved from db)
    -q    quiet mode, no output of htab, can still generate alignment if specified.
    -x    expanded output, includes two additional columns: gathering threshold and details (name=value~~name=value...)
    -Z    flag for debug mode, output debug information

	For output protein sequence alignment by hmmsearch (options -A, -B, -C, -D, -E, -F);
  at least one of the following options must be specified.

    -A    file_name (default: protein_alignment.XXX)
          If the input to htab.pl is by "cat", the alignment is saved in the directory
          included in "file_name" as "file_name.XXX" where XXX is the format "msf",
          "fa", or "mul".  If the input to htab.pl is by "ls",, the file_name will be
          ignored and output file names are the original file names appended with ".aligned"
          and saved in the same directory of the original files.

    -B    number (default: -2000)
          first bit score cutoff applied to overall score of the whole protein

    -C    number (default: -2000)
          second bit score cutoff applied to each fragment in a protein

    -D    number (default: 100)
          first E-value cutoff applied to overall score of the whole protein
	  (Note: a selected sequence must satisfy both bit score and E-value cutoff)

    -E    number (default: 100)
          second E-value cutoff applied to each fragment in a protein

    -F    format (default: msf)
          file format: msf, fasta, mul


    Description of the output format (tab-delimited, one line per domain hit)
    col  perl-col   description
    1      [0]      HMM accession                        
    2      [1]      Date of the htab job          
    3      [2]      Length of the HMM (from database)
    4      [3]      Search method (typically hmmsearch or hmmpfam)
    5      [4]      Name of the database file
    6      [5]      Protein accession
    7      [6]      Start position of HMM match - hmm-f
    8      [7]      End position of HMM match - hmm-t        
    9      [8]      Start position of the protein - seq-f
    10     [9]      End position of the protein  - seq-t
    11     [10]     (unassigned)
    12     [11]     Domain score
    13     [12]     Total score
    14     [13]     Domain number
    15     [14]     Total number of domains
    16     [15]     Biological description of the HMM (maybe truncated by hmmsearch or hmmpfam, but
                               can be recovered from DB using hmm_com_name if -s is not used)
    17     [16]     Biological description of the protein (maybe truncated by hmmsearch or hmmpfam)
    18     [17]     Trusted cutoff of the HMM (from database)
    19     [18]     Noise cutoff of the HMM (from database)
    20     [19]     Expect value for the whole match
    21     [20]     Expect value for the domain match

EXAMPLE
   ls  xxx/xxxx/xxxx/file_name* | htab.pl -f
   cat xxx/xxxx/xxxx/file_name* | htab.pl

_EOT_

	my ( %info );

    # parse command line options
    &get_options(\%info, $usage);
	if ( $info{no_db} ) {
		$info{db_proc} = undef;
	} else {
	
	# open database
		$info{db_proc} = DBI->connect( "dbi:SQLite:$info{dbEgad}", "", "", {PrintError=>0,RaiseError=>0,AutoCommit=>0} );
		if ( !defined $info{db_proc} ) {
			die "could not connect to database: " . $DBI::errstr;
		}
	}

	# input from list of files
	if($info{file}){
		my @file = <>;
		$info{align_file} = "";
		for (@file) {
		    my $file = $1 if($_ =~ /^(\S+)/);
		    print $file,"\n";
	    
		    if(!(-s $file)) {
			print "***Error: can not find file $file or it has zero size\n";
			next;
		    }
		    &parse_hmm_hits($file, $info{db}, $info{db_proc}, $usage, $info{debug}, $info{align_output}, $info{align_file}, $info{b1_cutoff}, $info{b2_cutoff}, $info{e1_cutoff}, $info{e2_cutoff}, $info{format}, $info{quiet}, $info{noise_cutoff}, $info{trusted_cutoff}, '', '', '', '', '', '', $info{multi}, $info{expanded_output});
		}

	# input from stdin
	} else {
		&parse_hmm_hits('', $info{db}, $info{db_proc}, $usage, $info{debug}, $info{align_output}, $info{align_file}, $info{b1_cutoff}, $info{b2_cutoff}, $info{e1_cutoff}, $info{e2_cutoff}, $info{format}, $info{quiet}, $info{noise_cutoff}, $info{trusted_cutoff}, '', '', '', '', '', '', $info{multi}, $info{expanded_output});
    }

	# close and unlock database
    if ( defined $info{db_proc} ) {
    	$info{db_proc}->disconnect if(defined $info{db_proc});
    }

    exit(0);
}
sub get_options {
    use strict;
    use Getopt::Std;
    use vars qw($opt_A $opt_B $opt_C $opt_D $opt_E $opt_F $opt_Z $opt_d $opt_f $opt_h $opt_m $opt_n $opt_q $opt_s $opt_t $opt_x );
    my ($info_r, $usage) = @_;
    our $defaultEgad;
    
    getopts('A:B:C:D:E:F:Zfhmn:qst:d:x') or die "Wrong input options. \n"; #get options
    die "$usage" if($opt_h);
    $$info_r{debug} = 1 if($opt_Z);
    $$info_r{file} = 1 if($opt_f);
    $$info_r{quiet} = 1 if($opt_q);
    $$info_r{multi} = 1 if($opt_m);
    if ( $opt_x ) {
    	$$info_r{expanded_output} = 1;
    } else {
    	$$info_r{expanded_output} = 0;
    }
    $$info_r{no_db} = 0;
    if ($opt_s) { $$info_r{no_db} = 1 }
    $$info_r{noise_cutoff}   = ($opt_n ne '' ? $opt_n : '');
    $$info_r{trusted_cutoff} = ($opt_t ne '' ? $opt_t : '');
    $$info_r{align_file}     = ($opt_A ne '' ? $opt_A : "protein_alignment");
    $$info_r{b1_cutoff}      = ($opt_B ne '' ? $opt_B : -2000);
    $$info_r{b2_cutoff}      = ($opt_C ne '' ? $opt_C : -2000);
    $$info_r{e1_cutoff}      = ($opt_D ne '' ? $opt_D : 100);
    $$info_r{e2_cutoff}      = ($opt_E ne '' ? $opt_E : 100);
    $$info_r{format}         = ($opt_F ne '' ? $opt_F : "msf");
    $$info_r{align_output} = 1 if($opt_A ne '' or $opt_B ne '' or $opt_C ne '' or $opt_D ne '' or $opt_E ne '' or $opt_F ne '');
    if ( $$info_r{no_db} == 1 ) {
    	$opt_d = undef;
    } elsif ($opt_d) {
    	if ( ! -e $opt_d ) { die "SQLite database \"$opt_d\" does not exist." }
    } else {
    	$opt_d = $defaultEgad;
    }
    $$info_r{dbEgad} = $opt_d;
}