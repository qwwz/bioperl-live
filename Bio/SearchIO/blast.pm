# $Id$
#
# BioPerl module for Bio::SearchIO::blast
#
# Cared for by Jason Stajich <jason@bioperl.org>
#
# Copyright Jason Stajich
#
# You may distribute this module under the same terms as perl itself

# POD documentation - main docs before the code

# 20030409 - sac
#          PSI-BLAST full parsing support. Rollout of new
#          model which will remove Steve's old psiblast driver 
# 20030424 - jason
#          Megablast parsing fix as reported by Neil Saunders
# 20030427 - jason 
#          Support bl2seq parsing
# 20031124 - jason
#          Parse more blast statistics, lambda, entropy, etc
#          from WU-BLAST in frame-specific manner

=head1 NAME

Bio::SearchIO::blast - Event generator for event based parsing of
blast reports

=head1 SYNOPSIS

   # Do not use this object directly - it is used as part of the
   # Bio::SearchIO system.

    use Bio::SearchIO;
    my $searchio = new Bio::SearchIO(-format => 'blast',
                                     -file   => 't/data/ecolitst.bls');
    while( my $result = $searchio->next_result ) {
        while( my $hit = $result->next_hit ) {
            while( my $hsp = $hit->next_hsp ) {
                # ...
            }
        }
    }

=head1 DESCRIPTION

This object encapsulated the necessary methods for generating events
suitable for building Bio::Search objects from a BLAST report file.
Read the L<Bio::SearchIO> for more information about how to use this.

This driver can parse:

=over 4

=item * 

NCBI produced plain text BLAST reports from blastall, this also
includes PSIBLAST, PSITBLASTN, RPSBLAST, and bl2seq reports.  NCBI XML
BLAST output is parsed with the blastxml SearchIO driver

=item *

WU-BLAST all reports

=item *

Jim Kent's BLAST-like output from his programs (BLASTZ, BLAT)

=item *

BLAST-like output from Paracel BTK output

=back

=head2 bl2seq parsing

Since I cannot differentiate between BLASTX and TBLASTN since bl2seq
doesn't report the algorithm used - I assume it is BLASTX by default -
you can supply the program type with -report_type in the SearchIO
constructor i.e.

  my $parser = new Bio::SearchIO(-format => 'blast',
                                 -file => 'bl2seq.tblastn.report',
                                 -report_type => 'tblastn');

This only really affects where the frame and strand information are
put - they will always be on the $hsp-E<gt>query instead of on the
$hsp-E<gt>hit part of the feature pair for blastx and tblastn bl2seq
produced reports.  Hope that's clear...

=head1 FEEDBACK

=head2 Mailing Lists

User feedback is an integral part of the evolution of this and other
Bioperl modules. Send your comments and suggestions preferably to
the Bioperl mailing list.  Your participation is much appreciated.

  bioperl-l@bioperl.org              - General discussion
  http://bioperl.org/MailList.shtml  - About the mailing lists

=head2 Reporting Bugs

Report bugs to the Bioperl bug tracking system to help us keep track
of the bugs and their resolution. Bug reports can be submitted via
email or the web:

  bioperl-bugs@bioperl.org
  http://bugzilla.bioperl.org/

=head1 AUTHOR - Jason Stajich

Email Jason Stajich jason-at-bioperl.org

=head1 CONTRIBUTORS

Steve Chervitz sac-at-bioperl.org

=head1 APPENDIX

The rest of the documentation details each of the object methods.
Internal methods are usually preceded with a _

=cut


# Let the code begin...'



package Bio::SearchIO::blast;

use Bio::SearchIO::IteratedSearchResultEventBuilder;

use strict;
use vars qw(@ISA %MAPPING %MODEMAP 
            $DEFAULT_BLAST_WRITER_CLASS 
            $MAX_HSP_OVERLAP
            $DEFAULT_SIGNIF
            $DEFAULT_SCORE
	    $DEFAULTREPORTTYPE
           );

use Bio::SearchIO;

@ISA = qw(Bio::SearchIO );

BEGIN { 
    # mapping of NCBI Blast terms to Bioperl hash keys
    %MODEMAP = (
                'BlastOutput'        => 'result',
                'Iteration'          => 'iteration',
                'Hit'                => 'hit',
                'Hsp'                => 'hsp'
                );

    # This should really be done more intelligently, like with
    # XSLT

    %MAPPING = 
        ( 
          'Hsp_bit-score'  => 'HSP-bits',
          'Hsp_score'      => 'HSP-score',
          'Hsp_evalue'     => 'HSP-evalue',
          'Hsp_pvalue'     => 'HSP-pvalue',
          'Hsp_query-from' => 'HSP-query_start',
          'Hsp_query-to'   => 'HSP-query_end',
          'Hsp_hit-from'   => 'HSP-hit_start',
          'Hsp_hit-to'     => 'HSP-hit_end',
          'Hsp_positive'   => 'HSP-conserved',
          'Hsp_identity'   => 'HSP-identical',
          'Hsp_gaps'       => 'HSP-hsp_gaps',
          'Hsp_hitgaps'    => 'HSP-hit_gaps',
          'Hsp_querygaps'  => 'HSP-query_gaps',
          'Hsp_qseq'       => 'HSP-query_seq',
          'Hsp_hseq'       => 'HSP-hit_seq',
          'Hsp_midline'    => 'HSP-homology_seq',
          'Hsp_align-len'  => 'HSP-hsp_length',
          'Hsp_query-frame'=> 'HSP-query_frame',
          'Hsp_hit-frame'  => 'HSP-hit_frame',
	  'Hsp_links'      => 'HSP-links',
	  'Hsp_group'      => 'HSP-hsp_group',

          'Hit_id'        => 'HIT-name',
          'Hit_len'       => 'HIT-length',
          'Hit_accession' => 'HIT-accession',
          'Hit_def'       => 'HIT-description',
          'Hit_signif'    => 'HIT-significance',
          # For NCBI blast, the description line contains bits.
          # For WU-blast, the  description line contains score.
          'Hit_score'     => 'HIT-score',
          'Hit_bits'      => 'HIT-bits',

          'Iteration_iter-num'   => 'ITERATION-number',
          'Iteration_converged'  => 'ITERATION-converged',

          'BlastOutput_program'  => 'RESULT-algorithm_name',
          'BlastOutput_version'  => 'RESULT-algorithm_version',
          'BlastOutput_query-def'=> 'RESULT-query_name',
          'BlastOutput_query-len'=> 'RESULT-query_length',
          'BlastOutput_query-acc'=> 'RESULT-query_accession',
          'BlastOutput_querydesc'=> 'RESULT-query_description',
          'BlastOutput_db'       => 'RESULT-database_name',
          'BlastOutput_db-len'   => 'RESULT-database_entries',
          'BlastOutput_db-let'   => 'RESULT-database_letters',
          'BlastOutput_inclusion-threshold'   => 'RESULT-inclusion_threshold',

          'Parameters_matrix'    => { 'RESULT-parameters' => 'matrix'},
          'Parameters_expect'    => { 'RESULT-parameters' => 'expect'},
          'Parameters_include'   => { 'RESULT-parameters' => 'include'},
          'Parameters_sc-match'  => { 'RESULT-parameters' => 'match'},
          'Parameters_sc-mismatch' => { 'RESULT-parameters' => 'mismatch'},
          'Parameters_gap-open'  =>   { 'RESULT-parameters' => 'gapopen'},
          'Parameters_gap-extend'=>   { 'RESULT-parameters' => 'gapext'},
          'Parameters_filter'    =>  {'RESULT-parameters' => 'filter'},
          'Parameters_allowgaps' =>   { 'RESULT-parameters' => 'allowgaps'},
	  'Parameters_full_dbpath' => { 'RESULT-parameters' => 'full_dbpath'},
          'Statistics_db-len'    => {'RESULT-statistics' => 'dbentries'},
          'Statistics_db-let'    => { 'RESULT-statistics' => 'dbletters'},
          'Statistics_hsp-len'   => { 'RESULT-statistics' => 'effective_hsplength'},
          'Statistics_query-len'   => { 'RESULT-statistics' => 'querylength'},
          'Statistics_eff-space' => { 'RESULT-statistics' => 'effectivespace'},
          'Statistics_eff-spaceused' => { 'RESULT-statistics' => 'effectivespaceused'},
          'Statistics_eff-dblen' => { 'RESULT-statistics' => 'effectivedblength'},
          'Statistics_kappa'     => { 'RESULT-statistics' => 'kappa' },
          'Statistics_lambda'    => { 'RESULT-statistics' => 'lambda' },
          'Statistics_entropy'   => { 'RESULT-statistics' => 'entropy'},
	  'Statistics_gapped_kappa' => { 'RESULT-statistics' => 'kappa_gapped' },
          'Statistics_gapped_lambda' => { 'RESULT-statistics' => 'lambda_gapped' },
          'Statistics_gapped_entropy' => { 'RESULT-statistics' => 'entropy_gapped'},
	  
          'Statistics_framewindow'=> { 'RESULT-statistics' => 'frameshiftwindow'},
          'Statistics_decay'=> { 'RESULT-statistics' => 'decayconst'},

          'Statistics_T'=> { 'RESULT-statistics' => 'T'},
          'Statistics_A'=> { 'RESULT-statistics' => 'A'},
          'Statistics_X1'=> { 'RESULT-statistics' => 'X1'},
          'Statistics_X2'=> { 'RESULT-statistics' => 'X2'},
          'Statistics_X3'=> { 'RESULT-statistics' => 'X3'},
          'Statistics_S1'=> { 'RESULT-statistics' => 'S1'},
          'Statistics_S2'=> { 'RESULT-statistics' => 'S2'},
	  
,         'Statistics_X1_bits'=> { 'RESULT-statistics' => 'X1_bits'},
          'Statistics_X2_bits'=> { 'RESULT-statistics' => 'X2_bits'},
          'Statistics_X3_bits'=> { 'RESULT-statistics' => 'X3_bits'},
          'Statistics_S1_bits'=> { 'RESULT-statistics' => 'S1_bits'},
          'Statistics_S2_bits'=> { 'RESULT-statistics' => 'S2_bits'},
	  
	  'Statistics_hit_to_db' => { 'RESULT-statistics'          => 'Hits_to_DB'},
	  'Statistics_num_extensions' => { 'RESULT-statistics'     => 'num_extensions'},
	  'Statistics_num_extensions' => { 'RESULT-statistics'     => 'num_extensions'},
	  'Statistics_num_suc_extensions' => { 'RESULT-statistics' => 'num_successful_extensions'},
	  'Statistics_seqs_better_than_cutoff' => { 'RESULT-statistics' 
							           => 'seqs_better_than_cutoff'},
	  'Statistics_posted_date' => { 'RESULT-statistics' => 'posted_date'},
	  
          # WU-BLAST stats
          'Statistics_DFA_states'=> { 'RESULT-statistics' => 'num_dfa_states'},
          'Statistics_DFA_size'=> { 'RESULT-statistics' => 'dfa_size'},

          'Statistics_search_cputime' => { 'RESULT-statistics' => 'search_cputime'},
          'Statistics_total_cputime' => { 'RESULT-statistics' => 'total_cputime'},
          'Statistics_search_actualtime' => { 'RESULT-statistics' => 'search_actualtime'},
          'Statistics_total_actualtime' => { 'RESULT-statistics' => 'total_actualtime'},

          'Statistics_noprocessors' => { 'RESULT-statistics' => 'no_of_processors'},
          'Statistics_neighbortime' => { 'RESULT-statistics' => 'neighborhood_generate_time'},
          'Statistics_starttime' => { 'RESULT-statistics' => 'start_time'},
          'Statistics_endtime' => { 'RESULT-statistics' => 'end_time'},
	  'Statistics_ctxfactor' => { 'RESULT-statistics' => 'ctxfactor'},
          );
    # add WU-BLAST Frame-Based Statistics
    for my $frame ( 0..3 ) {
	for my $strand ( '+', '-') {
	    for my $ind ( qw(length efflength E S W T X X_gapped E2 
			     E2_gapped S2) ) {
		$MAPPING{"Statistics_frame$strand$frame\_$ind"} = 
		{ 'RESULT-statistics' => "Frame$strand$frame\_$ind" }
	    }
	    for my $val ( qw(lambda kappa entropy ) ) {
		for my $type ( qw(used computed gapped) ) {
		    my $key ="Statistics_frame$strand$frame\_$val\_$type";
		    my $val = { 'RESULT-statistics' => "Frame$strand$frame\_$val\_$type" };
		    $MAPPING{$key} = $val;
		}
	    }
	}      
    }    
    $DEFAULT_BLAST_WRITER_CLASS = 'Bio::Search::Writer::HitTableWriter';
    $MAX_HSP_OVERLAP  = 2;  # Used when tiling multiple HSPs.
    $DEFAULTREPORTTYPE = 'BLASTP'; # for bl2seq
}

=head2 new

 Title   : new
 Usage   : my $obj = new Bio::SearchIO::blast(%args);
 Function: Builds a new Bio::SearchIO::blast object 
 Returns : Bio::SearchIO::blast
 Args    : Key-value pairs:
           -fh/-file => filehandle/filename to BLAST file
           -format   => 'blast'
           -report_type => 'blastx', 'tblastn', etc -- only for bl2seq
                           reports when you want to distinguish between
                           tblastn and blastx reports (this only controls
                           where the frame information is put - on the query
                           or subject object.
           -inclusion_threshold => e-value threshold for inclusion in the
                                   PSI-BLAST score matrix model (blastpgp)
           -signif      => float or scientific notation number to be used
                           as a P- or Expect value cutoff
           -score       => integer or scientific notation number to be used
                           as a blast score value cutoff
           -bits        => integer or scientific notation number to be used
                           as a bit score value cutoff
           -hit_filter  => reference to a function to be used for
                           filtering hits based on arbitrary criteria.
                           All hits of each BLAST report must satisfy 
                           this criteria to be retained. 
                           If a hit fails this test, it is ignored.
                           This function should take a
                           Bio::Search::Hit::BlastHit.pm object as its first
                           argument and return true
                           if the hit should be retained.
                           Sample filter function:
                              -hit_filter => sub { $hit = shift;
                                                   $hit->gaps == 0; },
                           (Note: -filt_func is synonymous with -hit_filter)
           -overlap     => integer. The amount of overlap to permit between
                           adjacent HSPs when tiling HSPs. A reasonable value is 2.
                           Default = $Bio::SearchIO::blast::MAX_HSP_OVERLAP.

            The following criteria are not yet supported:
            (these are probably best applied within this module rather than in the 
             event handler since they would permit the parser to take some shortcuts.)

           -check_all_hits => boolean. Check all hits for significance against
                              significance criteria.  Default = false.
                              If false, stops processing hits after the first
                              non-significant hit or the first hit that fails
                              the hit_filter call. This speeds parsing,
                              taking advantage of the fact that the hits
                              are processed in the order they appear in the report.
           -min_query_len => integer to be used as a minimum for query sequence length.
                             Reports with query sequences below this length will
                             not be processed. Default = no minimum length.
           -best        => boolean. Only process the best hit of each report;
                           default = false.

=cut

sub _initialize {
    my ($self,@args) = @_;
    $self->SUPER::_initialize(@args);

    # Blast reports require a specialized version of the SREB due to the 
    # possibility of iterations (PSI-BLAST). Forwarding all arguments to it.
    # An issue here is that we want to set new default object factories if none are
    # supplied.

    my $handler = new Bio::SearchIO::IteratedSearchResultEventBuilder(@args);
    $self->attach_EventHandler($handler);

    # Optimization: caching the EventHandler since it's use a lot during the parse.
    $self->{'_handler_cache'} = $handler;

    my($min_qlen, $check_all, $overlap, $best,$rpttype ) =
           $self->_rearrange([qw(MIN_LENGTH CHECK_ALL_HITS 
				 OVERLAP BEST 
				 REPORT_TYPE)], @args);

    defined $min_qlen && $self->min_query_length($min_qlen);
    defined $best && $self->best_hit_only($best);
    defined $check_all && $self->check_all_hits($check_all);
    defined $rpttype && ($self->{'_reporttype'} = $rpttype);
}


=head2 next_result

 Title   : next_result
 Usage   : my $hit = $searchio->next_result;
 Function: Returns the next Result from a search
 Returns : Bio::Search::Result::ResultI object
 Args    : none

=cut

sub next_result{
   my ($self) = @_;
   my $v = $self->verbose;
   my $data = '';
   my $flavor = '';
   $self->{'_seentop'} = 0;
   my ($reporttype,$seenquery,$reportline);
   my ($seeniteration,$found_again);
   my $incl_threshold = $self->inclusion_threshold;
   my $bl2seq_fix;
   $self->start_document();
   my (@hit_signifs);
   my $gapped_stats = 0; # for switching between gapped/ungapped
                         # lambda, K, H
   
   while( defined ($_ = $self->_readline )) {
       next if( /^\s+$/); # skip empty lines
       next if( /CPU time:/);
       next if( /^>\s*$/);

       if( /^([T]?BLAST[NPX])\s*(.+)$/i ||
	   /^(PSITBLASTN)\s+(.+)$/i ||
	   /^(RPS-BLAST)\s*(.+)$/i ||
	   /^(MEGABLAST)\s*(.+)$/i || 
	   /^(P?GENEWISE|HFRAME|SWN|TSWN)\s+(.+)/i #Paracel BTK
           ) {
 #          $self->debug("blast.pm: Start of new report: $1 $2\n");
	   if( $self->{'_seentop'} ) {
               # This handles multi-result input streams
               $self->_pushback($_);
               $self->in_element('hsp') && 
                   $self->end_element({ 'Name' => 'Hsp'});
               $self->in_element('hit') && 
                   $self->end_element({ 'Name' => 'Hit'});
               $self->within_element('iteration') &&
		   $self->end_element({ 'Name' => 'Iteration'});
               $self->end_element({ 'Name' => 'BlastOutput'});
               return $self->end_document();
           }
           $self->_start_blastoutput;
           $reporttype = $1;
           $reportline = $_; # to fix the fact that RPS-BLAST output is wrong
           $self->element({ 'Name' => 'BlastOutput_program',
                            'Data' => $reporttype});

           $self->element({ 'Name' => 'BlastOutput_version',
                            'Data' => $2});
           $self->element({ 'Name' => 'BlastOutput_inclusion-threshold',
                            'Data' => $incl_threshold});
       } elsif ( /^Searching/ ) {
#	   $self->debug("blast.pm: Searching found...\n");
           $self->in_element('hsp') && 
               $self->end_element({ 'Name' => 'Hsp'});
           $self->in_element('hit') && 
               $self->end_element({ 'Name' => 'Hit'});

           if( defined $seeniteration ) {
	       $self->within_element('iteration') &&
		   $self->end_element({ 'Name' => 'Iteration'});               
               $self->_start_iteration;
           } else { 
               $self->_start_iteration;
           }
           $seeniteration = 1;
       } elsif ( /^Query=\s*(.*)$/ ) {
           #$self->debug("blast.pm: Query= found...$_\n");
           my $q = $1;
           my $size = 0;
	   
           if( defined $seenquery ) { 
	       $self->_pushback($reportline) if $reportline;
               $self->_pushback($_);
	       $self->in_element('hsp') &&
		   $self->end_element({'Name'=> 'Hsp'});
	       $self->in_element('hit') &&
		   $self->end_element({'Name'=> 'Hit'});
	       $self->within_element('iteration') &&
		   $self->end_element({'Name'=> 'Iteration'});
	       if( $bl2seq_fix ) { 
		   $self->element({ 'Name' => 'BlastOutput_program',
				    'Data' => $reporttype});
	       }
	       $self->end_element({'Name' => 'BlastOutput'});
               return $self->end_document();
           } else { 
               if( ! defined $reporttype ) {
                   $self->_start_blastoutput;
		   if( defined $seeniteration ) {
		       $self->in_element('iteration') &&
			   $self->end_element({ 'Name' => 'Iteration'});
		       $self->_start_iteration;
		   } else { 
		       $self->_start_iteration;
		   }
		   $seeniteration = 1;
               }
           }
           $seenquery = $q;
           $_ = $self->_readline;
           while( defined ($_) ) {
               if( /^Database:/ ) {
		   $self->_pushback($_);
		   last;
	       }
               chomp;               
               if( /\((\-?[\d,]+)\s+letters.*\)/ ) {
                   $size = $1;
                   $size =~ s/,//g;
                   last;
               } else { 
                   $q .= " $_";
                   $q =~ s/ +/ /g;
                   $q =~ s/^ | $//g;
               }

               $_ = $self->_readline;
           }
           chomp($q);
           my ($nm,$desc) = split(/\s+/,$q,2);
           $self->element({ 'Name' => 'BlastOutput_query-def',
                            'Data' => $nm});
           $self->element({ 'Name' => 'BlastOutput_query-len', 
                            'Data' => $size});
           defined $desc && $desc =~ s/\s+$//;
           $self->element({ 'Name' => 'BlastOutput_querydesc', 
                            'Data' => $desc});
           my ($acc,$version) = &_get_accession_version($nm);
	   $version = defined($version) && length($version) ? ".$version" : "";
           $acc = '' unless defined($acc);
	   $self->element({ 'Name' =>  'BlastOutput_query-acc',
			    'Data'  => "$acc$version"});
       } elsif( /Sequences producing significant alignments:/ ) {
#           $self->debug("blast.pm: Processing NCBI-BLAST descripitons\n");
           $flavor = 'ncbi';
           # The next line is not necessarily whitespace in psiblast reports.
           # Also note that we must look for the end of this section by testing
           # for a line with a leading >. Blank lines occur with this section
           # for psiblast.

           if (! $self->in_element('iteration')) {
               $self->_start_iteration;
           }
	   
         descline:
           while( defined ($_ = $self->_readline() )) {
               if( /^>/ ) {
                   $self->_pushback($_);
                   last descline;
               } elsif( /([\d\.\+\-eE]+)\s+([\d\.\+\-eE]+)(\s+\d+)?\s*$/) {
		   # the last match is for gapped BLAST output
		   # which will report the number of HSPs for the Hit
                   my ($score, $evalue) = ($1, $2);
                   # Some data clean-up so e-value will appear numeric to perl
                   $evalue =~ s/^e/1e/i;
		   
		   # This to handle no-HSP case
		   my @line = split;
		   # we want to throw away the score, evalue
		   pop @line, pop @line;
		   # and N if it is present (of course they are not 
		   # really in that order, but it doesn't matter
		   if( $3 ) { pop @line }		   
		   
		   # add the last 2 entries s.t. we can reconstruct
		   # a minimal Hit object at the end of the day
		   push @hit_signifs, [ $evalue, $score,
					shift @line, join(' ', @line)];
               } elsif (/^CONVERGED/i) {
                   $self->element({ 'Name' => 'Iteration_converged',
                                    'Data' => 1});
               }
	       
           }
       } elsif( /Sequences producing High-scoring Segment Pairs:/ ) {
           # This block is for WU-BLAST, so we don't have to check for psi-blast stuff
           # skip the next line
#           $self->debug("blast.pm: Processing WU-BLAST descripitons\n");
           $_ = $self->_readline();
           $flavor = 'wu';

           if (! $self->in_element('iteration')) {
               $self->_start_iteration;
           }

            while( defined ($_ = $self->_readline() ) && 
                  ! /^\s+$/ ) {        
                my @line = split;
		pop @line; # throw away first number which is for 'N'col
		
		# add the last 2 entries to array s.t. we can reconstruct
		# a minimal Hit object at the end of the day
                push @hit_signifs, [ pop @line, pop @line, 
				     shift @line, join(' ', @line)];
           }
       } elsif ( /^Database:\s*(.+)$/ ) {
#           $self->debug("blast.pm: Database: $1\n");
           my $db = $1;
           while( defined($_ = $self->_readline) ) {
               if( /^\s+(\-?[\d\,]+|\S+)\s+sequences\;
                   \s+(\-?[\d,]+|\S+)\s+ # Deal with NCBI 2.2.8 OSX problems
                   total\s+letters/ox){
                   my ($s,$l) = ($1,$2);
                   $s =~ s/,//g;
                   $l =~ s/,//g;
                   $self->element({'Name' => 'BlastOutput_db-len',
                                   'Data' => $s});
                   $self->element({'Name' => 'BlastOutput_db-let',
                                   'Data' => $l});
                   last;
               } else {
                   chomp;
                   $db .= $_;
               }
           }
           $self->element({'Name' => 'BlastOutput_db',
                           'Data' => $db});
       } elsif( /^>\s*(\S+)\s*(.*)?/ ) {
           chomp;
#           $self->debug("blast.pm: Hit: $1\n");
           $self->in_element('hsp') && $self->end_element({ 'Name' => 'Hsp'});
           $self->in_element('hit') && $self->end_element({ 'Name' => 'Hit'});
	   # special case when bl2seq reports don't have a leading
	   # Query=
	   if( ! $self->within_element('result') ) {
	       $self->_start_blastoutput;
	       $self->_start_iteration;
           } elsif( ! $self->within_element('iteration') ) {
	       $self->_start_iteration;
	   }
	   $self->start_element({ 'Name' => 'Hit'});
           my $id = $1;
           my $restofline = $2;
#           $self->debug("Starting a hit: $1 $2\n");
	   $self->element({ 'Name' => 'Hit_id',
                            'Data' => $id});           
           my ($acc,$version) = &_get_accession_version($id);
           $self->element({ 'Name' =>  'Hit_accession',
                            'Data'  => $acc});           

           my $v = shift @hit_signifs;
           if( defined $v ) {
               $self->element({'Name' => 'Hit_signif',
                               'Data' => $v->[0]});
               $self->element({'Name' => 'Hit_score',
                               'Data' => $v->[1]});
           }
           while(defined($_ = $self->_readline()) ) {
               next if( /^\s+$/ );
               chomp;
               if(  /Length\s*=\s*([\d,]+)/ ) {
                   my $l = $1;
                   $l =~ s/\,//g;
                   $self->element({ 'Name' => 'Hit_len',
                                    'Data' => $l });
                   last;               
               } else { 
                   $restofline .= $_;
               }
           }
           $restofline =~ s/\s+/ /g;
           $self->element({ 'Name' => 'Hit_def',
                            'Data' => $restofline});       
       } elsif( /\s+(Plus|Minus) Strand HSPs:/i ) {
           next;
       } elsif( ($self->in_element('hit') || 
                 $self->in_element('hsp')) && # paracel genewise BTK
		m/Score\s*=\s*(\S+)\s*bits\s* # Bit score
                (?:\((\d+)\))?,                 # Raw score
		\s+Log\-Length\sScore\s*=\s*(\d+) # Log-Length score
                /ox) {
	   $self->in_element('hsp') && $self->end_element({'Name' => 'Hsp'});
           $self->start_element({'Name' => 'Hsp'});
#	   $self->debug( "Got paracel genewise HSP score=$1\n");
	   
           # Some data clean-up so e-value will appear numeric to perl
           my ($bits,$score, $evalue) = ($1,$2,$3);
           $evalue =~ s/^e/1e/i;
	   $self->element( { 'Name' => 'Hsp_score',
                             'Data' => $score});
           $self->element( { 'Name' => 'Hsp_bit-score',
                             'Data' => $bits});
           $self->element( { 'Name' => 'Hsp_evalue',
                             'Data' => $evalue});
       } elsif( ($self->in_element('hit') || 
                 $self->in_element('hsp')) && # paracel hframe BTK
		m/Score\s*=\s*([^,\s]+),     # Raw score
		\s*Expect\s*=\s*([^,\s]+),  # E-value
                \s*P(?:\(\S+\))?\s*=\s*([^,\s]+) # P-value
                /ox) {
	   $self->in_element('hsp') && $self->end_element({'Name' => 'Hsp'});
           $self->start_element({'Name' => 'Hsp'});
#	   $self->debug( "Got paracel hframe HSP score=$1\n");

	   # Some data clean-up so e-value will appear numeric to perl
           my ($score, $evalue, $pvalue) = ($1, $2, $3);
           $evalue = "1$evalue" if $evalue =~ /^e/;
           $pvalue = "1$pvalue" if $pvalue =~ /^e/;
	   
	   $self->element( { 'Name' => 'Hsp_score',
                             'Data' => $score});
           $self->element( { 'Name' => 'Hsp_evalue',
                             'Data' => $evalue});
           $self->element( {'Name'  => 'Hsp_pvalue',
                            'Data'  =>$pvalue});           
       } elsif( ($self->in_element('hit') || 
                 $self->in_element('hsp')) && # wublast
               m/Score\s*=\s*(\S+)\s*         # Bit score
                \(([\d\.]+)\s*bits\),         # Raw score
                \s*Expect\s*=\s*([^,\s]+),    # E-value
                \s*(?:Sum)?\s*                # SUM
                P(?:\(\d+\))?\s*=\s*([^,\s]+) # P-value
                (?:\s*,\s+Group\s*\=\s*(\d+))?    # HSP Group
                /ox 
                  ) { # wu-blast HSP parse
           $self->in_element('hsp') && $self->end_element({'Name' => 'Hsp'});
           $self->start_element({'Name' => 'Hsp'});
	   
           # Some data clean-up so e-value will appear numeric to perl
           my ($score, $bits, $evalue, $pvalue,$group) = ($1, $2, $3, $4, $5);
           $evalue =~ s/^e/1e/i;
           $pvalue =~ s/^e/1e/i;
	   
	   $self->element( { 'Name' => 'Hsp_score',
                             'Data' => $score});
           $self->element( { 'Name' => 'Hsp_bit-score',
                             'Data' => $bits});
           $self->element( { 'Name' => 'Hsp_evalue',
                             'Data' => $evalue});
           $self->element( {'Name'  => 'Hsp_pvalue',
                            'Data'  =>$pvalue});
	   if( defined $group ) {
	       $self->element( {'Name'  => 'Hsp_group',
				'Data'  => $group});
	   }

       } elsif( ($self->in_element('hit') || 
                 $self->in_element('hsp')) && # ncbi blast
                m/Score\s*=\s*(\S+)\s*bits\s* # Bit score
                (?:\((\d+)\))?,            # Missing for BLAT pseudo-BLAST fmt 
                \s*Expect(?:\(\d+\+?\))?\s*=\s*(\S+) # E-value
                /ox) { # parse NCBI blast HSP
           $self->in_element('hsp') && $self->end_element({ 'Name' => 'Hsp'});
	   
           # Some data clean-up so e-value will appear numeric to perl
           my ($bits,$score, $evalue) = ($1, $2, $3);
	   $evalue =~ s/^e/1e/i;
	   
           $self->start_element({'Name' => 'Hsp'});
           $self->element( { 'Name' => 'Hsp_score',
                             'Data' => $score});
           $self->element( { 'Name' => 'Hsp_bit-score',
                             'Data' => $bits});
           $self->element( { 'Name' => 'Hsp_evalue',
                             'Data' => $evalue});
	   $score = '' unless defined $score; # deal with BLAT which
                                              # has no score only bits
           #$self->debug("Got NCBI HSP score=$score, evalue $evalue\n") if $self->verbose > 0;
       } elsif( $self->in_element('hsp') &&
                m/Identities\s*=\s*(\d+)\s*\/\s*(\d+)\s*[\d\%\(\)]+\s*
                (?:,\s*Positives\s*=\s*(\d+)\/(\d+)\s*[\d\%\(\)]+\s*)? # pos only valid for Protein alignments
                (?:\,\s*Gaps\s*=\s*(\d+)\/(\d+))? # Gaps
                /oxi 
                ) {
           $self->element( { 'Name' => 'Hsp_identity',
                             'Data' => $1});
           $self->element( {'Name' => 'Hsp_align-len',
                            'Data' => $2});
           if( defined $3 ) {
               $self->element( { 'Name' => 'Hsp_positive',
                                 'Data' => $3});
           } else { 
               $self->element( { 'Name' => 'Hsp_positive',
                                 'Data' => $1});
           }
           if( defined $6 ) {
               $self->element( { 'Name' => 'Hsp_gaps',
                                 'Data' => $5});
           }
           
           $self->{'_Query'} = { 'begin' => 0, 'end' => 0};
           $self->{'_Sbjct'} = { 'begin' => 0, 'end' => 0};

           if( /(Frame\s*=\s*.+)$/ ) {
               # handle wu-blast Frame listing on same line
               $self->_pushback($1);
           }     
       } elsif( $self->in_element('hsp') &&
                /Strand\s*=\s*(Plus|Minus)\s*\/\s*(Plus|Minus)/i ) {
           # consume this event ( we infer strand from start/end)
	   unless( $reporttype ) {
	       $self->{'_reporttype'} = $reporttype = 'BLASTN';
	       $bl2seq_fix =1; # special case to resubmit the algorithm
	                       # reporttype
	   }
           next;
       } elsif( $self->in_element('hsp') &&
		/Links\s*=\s*(\S+)/ox ) {
	   $self->element({'Name' => 'Hsp_links',
			   'Data' => $1});
       } elsif( $self->in_element('hsp') &&
                /Frame\s*=\s*([\+\-][1-3])\s*(\/\s*([\+\-][1-3]))?/ ){
	   # this is for bl2seq only
	   unless( defined $reporttype) {
	       $bl2seq_fix = 1;
	       if( $1 && $2 ) { $reporttype = 'TBLASTX' }
	       else { $reporttype = 'BLASTX'; 
# we can't distinguish between BLASTX and TBLASTN straight from the report }
		  }
	       $self->{'_reporttype'} = $reporttype;
	   }
	   
           my ($queryframe,$hitframe);
           if( $reporttype eq 'TBLASTX' ) {
               ($queryframe,$hitframe) = ($1,$2);
               $hitframe =~ s/\/\s*//g;
           } elsif( $reporttype eq 'TBLASTN' ) {
               ($hitframe,$queryframe) = ($1,0);               
           } elsif( $reporttype eq 'BLASTX' ) {               
               ($queryframe,$hitframe) = ($1,0);
           } 
           $self->element({'Name' => 'Hsp_query-frame',
                           'Data' => $queryframe});
                      
           $self->element({'Name' => 'Hsp_hit-frame',
                           'Data' => $hitframe});
       } elsif(  /^Parameters:/ || /^\s+Database:\s+?/ || 
		 /^\s+Subset/ || /^\s*Lambda/ || /^\s*Histogram/ ||
                 ( $self->in_element('hsp') && /WARNING|NOTE/ )) {

           # Note: Lambda check was necessary to parse 
	   # t/data/ecoli_domains.rpsblast AND to parse bl2seq
#           $self->debug("blast.pm: found parameters section \n");
	   
           $self->in_element('hsp') && $self->end_element({'Name' => 'Hsp'});
           $self->in_element('hit') && $self->end_element({'Name' => 'Hit'});
           
	   # This is for the case when we specify -b 0 (or B=0 for WU-BLAST)
	   # and still want to construct minimal Hit objects
	   while(my $v = shift @hit_signifs) {
	       next unless defined $v;
	       $self->start_element({ 'Name' => 'Hit'});
	       my $id  = $v->[2];
	       my $desc= $v->[3];
	       $self->element({ 'Name' => 'Hit_id',
				'Data' => $id});
	       my ($acc,$version) = &_get_accession_version($id);
	       $self->element({ 'Name' =>  'Hit_accession',
				'Data'  => $acc});
	       
	       if( defined $v ) {
		   $self->element({'Name' => 'Hit_signif',
				   'Data' => $v->[0]});
		   $self->element({'Name' => 'Hit_score',
				   'Data' => $v->[1]});
	       }
	       $self->element({ 'Name' => 'Hit_def',
				'Data' => $desc});
	       $self->end_element({'Name' => 'Hit'});
	   }

	   $self->within_element('iteration') && 
	       $self->end_element({'Name' => 'Iteration'});

           next if /^\s+Subset/;
	   my $blast = ( /^(\s+Database\:)|(\s*Lambda)/ ) ? 'ncbi' : 'wublast';
	   if( /^\s*Histogram/ ) {
	       $blast = 'btk';
	   }
	   
           my $last = '';
           # default is that gaps are allowed
           $self->element({'Name' => 'Parameters_allowgaps',
                           'Data' => 'yes'});
           while( defined ($_ = $self->_readline ) ) {
	       if( /^(PSI)?([T]?BLAST[NPX])\s*(.+)/i ||
		   /^MEGABLAST\s*(.+)/i ||
		   /^(P?GENEWISE|HFRAME|SWN|TSWN)\s+(.+)/i #Paracel BTK
		   ) {
                   $self->_pushback($_);
                   # let's handle this in the loop
                   last;
               } elsif( /^Query=/ ) {        
                   $self->_pushback($reportline) if $reportline;
                   $self->_pushback($_);
		   # -- Superfluous I think, but adding nonetheless
                   $self->in_element('hsp') &&
		       $self->end_element({'Name'=> 'Hsp'});
		   $self->in_element('hit') &&
		       $self->end_element({'Name'=> 'Hit'});
		   # --
		   if( $bl2seq_fix ) { 
		       $self->element({ 'Name' => 'BlastOutput_program',
					'Data' => $reporttype});
		   }
		   $self->end_element({ 'Name' => 'BlastOutput'});
                   return $self->end_document();
               }

               # here is where difference between wublast and ncbiblast
               # is better handled by different logic
               if( /Number of Sequences:\s+([\d\,]+)/i ||
		   /of sequences in database:\s+(\-?[\d,]+)/i) {
                   my $c = $1;
                   $c =~ s/\,//g;
                   $self->element({'Name' => 'Statistics_db-len',
                                   'Data' => $c});
               } elsif ( /letters in database:\s+(\-?[\d,]+)/i) {           
                   my $s = $1;
                   $s =~ s/,//g;
                   $self->element({'Name' => 'Statistics_db-let',
                                   'Data' => $s});
               } elsif( $blast eq 'btk' ) { 
		   next;
	       } elsif( $blast eq 'wublast' ) {
                   if( /E=(\S+)/ ) {
                       $self->element({'Name' => 'Parameters_expect',
                                       'Data' => $1});
                   } elsif( /nogaps/ ) {
                       $self->element({'Name' => 'Parameters_allowgaps',
                                       'Data' => 'no'});
                   } elsif( /ctxfactor=(\S+)/ ) {
		       $self->element({'Name' => 'Statistics_ctxfactor',
				       'Data' => $1});
		   } elsif( $last =~ /(Frame|Strand)\s+MatID\s+Matrix name/i ){
		       my $firstgapinfo = 1;
		       my $frame = undef;		       
		       while( defined($_) && ! /^\s+$/) { 
			   s/^\s+//;
			   s/\s+$//;
			   if( $firstgapinfo && 
			       s/Q=(\d+),R=(\d+)\s+//x ) {
			       $firstgapinfo = 0;
			       
			       $self->element({'Name' => 'Parameters_gap-open',
					       'Data' => $1});
			       $self->element({'Name' => 'Parameters_gap-extend',
					       'Data' => $2});
			       my @fields = split;
			       
			       for my $type ( qw(lambda_gapped
						 kappa_gapped
						 entropy_gapped) ) {
				   next if $type eq 'n/a';
				   if( ! @fields ) {
				       warn "fields is empty for $type\n";
				       next;
				   }
				   $self->element({'Name' => "Statistics_frame$frame\_$type",
						   'Data' => shift @fields});
			       }
			   } else { 
			       my ($frameo,$matid,$matrix,@fields) = split;
			       if( ! defined $frame ) { 
				   # keep some sort of default feature I guess
				   # even though this is sort of wrong
				   $self->element({'Name' => 'Parameters_matrix',
						   'Data' => $matrix});
				   $self->element({'Name' => 'Statistics_lambda',
						   'Data' => $fields[0]});
				   $self->element({'Name' => 'Statistics_kappa',
						   'Data' => $fields[1]});
				   $self->element({'Name' => 'Statistics_entropy',
						   'Data' => $fields[2]});
			       }
			       $frame = $frameo;
			       my $ii = 0;
			       for my $type ( qw(lambda_used
						 kappa_used
						 entropy_used
						 lambda_computed
						 kappa_computed
						 entropy_computed) ) {
				   my $f = $fields[$ii];
				   next unless defined $f; # deal with n/a
				   if( $f eq 'same' ) { 
				       $f = $fields[$ii-3];
				   }
				   $ii++;
				   $self->element({'Name' => "Statistics_frame$frame\_$type",
						   'Data' => $f});
				   
			       }
			   }			   
			   # get the next line
			   $_ = $self->_readline;
		       }
		       $last = $_;
		   } elsif( $last =~ /(Frame|Strand)\s+MatID\s+Length/i ){
		       my $frame = undef;
		       while( defined($_) && ! /^\s+/) { 
			   s/^\s+//;
			   s/\s+$//;
			   my @fields = split;
			   if( @fields <= 3 ) { 
			       for my $type ( qw(X_gapped E2_gapped S2) ) {
				   last unless @fields;
				   $self->element({'Name' => "Statistics_frame$frame\_$type",
						   'Data' => shift @fields});
			       }
			   } else  {
			       #print STDERR "fields are @fields\n";
			       for my $type ( qw(length
						 efflength
						 E S W T X E2 S2) ) {
				   $self->element({'Name' => "Statistics_frame$frame\_$type",
						   'Data' => shift @fields});
			       }
			   }
			   $_ = $self->_readline;
		       }
		       $last = $_;
		   } elsif( /(\S+\s+\S+)\s+DFA:\s+(\S+)\s+\((.+)\)/ ) {
                       if( $1 eq 'states in') { 
                           $self->element({'Name' => 'Statistics_DFA_states',
                                           'Data' => "$2 $3"});
                       } elsif( $1 eq 'size of') {
                           $self->element({'Name' => 'Statistics_DFA_size',
                                           'Data' => "$2 $3"});
                       }
                   } elsif( m/^\s+Time to generate neighborhood:\s+
			    (\S+\s+\S+\s+\S+)/x ) { 
                       $self->element({'Name' => 'Statistics_neighbortime',
                                       'Data' => $1});
                   } elsif( /processors\s+used:\s+(\d+)/ ) {
                          $self->element({'Name' => 'Statistics_noprocessors',
                                           'Data' => $1});
                   } elsif( m/^\s+(\S+)\s+cpu\s+time:\s+# cputype
			    (\S+\s+\S+\s+\S+)           # cputime
			    \s+Elapsed:\s+(\S+)/x ) {
                       my $cputype = lc($1);
                       $self->element({'Name' => "Statistics_$cputype\_cputime",
                                       'Data' => $2});
                       $self->element({'Name' => "Statistics_$cputype\_actualtime",
                                       'Data' => $3});
                   } elsif( /^\s+Start:/ ) {
                       my ($junk,$start,$stime,
			   $end,$etime) = split(/\s+(Start|End)\:\s+/,$_);
                       chomp($stime);
                       $self->element({'Name' => 'Statistics_starttime',
                                       'Data' => $stime});
                       chomp($etime);
                       $self->element({'Name' => 'Statistics_endtime',
                                       'Data' => $etime});
                   } elsif( /^\s+Database:\s+(\S+)/ ) {
		       $self->element({'Name' => 'Parameters_full_dbpath',
				       'Data' => $1});
		       
		   } elsif( /^\s+Posted:\s+(.+)/ ) {
		       my $d = $1;
		       chomp($d);
		       $self->element({'Name' => 'Statistics_posted_date',
				       'Data' => $d});
		   }
               } elsif ( $blast eq 'ncbi' ) {
		   
                   if( m/^Matrix:\s+(.+)\s*$/oxi ) {
                       $self->element({'Name' => 'Parameters_matrix',
                                       'Data' => $1});                       
                   } elsif( /^Gapped/ ) { 
		       $gapped_stats = 1;
		   } elsif( /^Lambda/ ) {
                       $_ = $self->_readline;
                       s/^\s+//;
                       my ($lambda, $kappa, $entropy) = split;
		       if( $gapped_stats ) { 
			   $self->element({'Name' => "Statistics_gapped_lambda",
					   'Data' => $lambda});
			   $self->element({'Name' => "Statistics_gapped_kappa",
					   'Data' => $kappa});
			   $self->element({'Name' => "Statistics_gapped_entropy",
					   'Data' => $entropy});
		       } else { 
			   $self->element({'Name' => "Statistics_lambda",
					   'Data' => $lambda});
			   $self->element({'Name' => "Statistics_kappa",
					   'Data' => $kappa});
			   $self->element({'Name' => "Statistics_entropy",
					   'Data' => $entropy});
		       }
                   } elsif( m/effective\s+search\s+space\s+used:\s+(\d+)/ox ) {
                       $self->element({'Name' => 'Statistics_eff-spaceused',
                                       'Data' => $1});                       
                   } elsif( m/effective\s+search\s+space:\s+(\d+)/ox ) {
                       $self->element({'Name' => 'Statistics_eff-space',
                                       'Data' => $1});
                   } elsif( m/Gap\s+Penalties:\s+Existence:\s+(\d+)\,
			    \s+Extension:\s+(\d+)/ox) {
		       $self->element({'Name' => 'Parameters_gap-open',
                                       'Data' => $1});
                       $self->element({'Name' => 'Parameters_gap-extend',
                                       'Data' => $2});
                   } elsif( /effective\s+HSP\s+length:\s+(\d+)/ ) {
                        $self->element({'Name' => 'Statistics_hsp-len',
                                        'Data' => $1});
                   } elsif( /effective\s+length\s+of\s+query:\s+([\d\,]+)/ ) {
                       my $c = $1;
                       $c =~ s/\,//g;
                        $self->element({'Name' => 'Statistics_query-len',
                                        'Data' => $c});
                   } elsif( /effective\s+length\s+of\s+database:\s+([\d\,]+)/){
                       my $c = $1;
                       $c =~ s/\,//g;
                       $self->element({'Name' => 'Statistics_eff-dblen',
                                       'Data' => $c});
                   } elsif( /^(T|A|X1|X2|X3|S1|S2):\s+(\d+(\.\d+)?)\s+(?:\(\s*(\d+\.\d+) bits\))?/ ) {
		       my $v = $2;
		       chomp($v);
                       $self->element({'Name' => "Statistics_$1",
                                       'Data' => $v});
		       if( defined $4 ) {
			   $self->element({'Name' => "Statistics_$1_bits",
					   'Data' => $4});
		       }
		   } elsif( m/frameshift\s+window\,
			    \s+decay\s+const:\s+(\d+)\,\s+([\.\d]+)/x ) {
		       $self->element({'Name'=> 'Statistics_framewindow',
				       'Data' => $1});
		       $self->element({'Name'=> 'Statistics_decay',
				       'Data' => $2});
		   } elsif( m/^Number\s+of\s+Hits\s+to\s+DB:\s+(\S+)/ox ) {
		       $self->element({'Name' => 'Statistics_hit_to_db',
				       'Data' => $1});
		   } elsif( m/^Number\s+of\s+extensions:\s+(\S+)/ox ) {
		       $self->element({'Name' => 'Statistics_num_extensions',
				       'Data' => $1});
		   } elsif( m/^Number\s+of\s+successful\s+extensions:\s+
			    (\S+)/ox ) {
		       $self->element({'Name' => 'Statistics_num_suc_extensions',
				       'Data' => $1});
		   } elsif( m/^Number\s+of\s+sequences\s+better\s+than\s+
			    (\S+):\s+(\d+)/ox ) {
		       $self->element({'Name' => 'Parameters_expect',
				       'Data' => $1});
		       $self->element({'Name' => 'Statistics_seqs_better_than_cutoff',
				       'Data' => $2});
		   } elsif( /^\s+Posted\s+date:\s+(.+)/ ) {
		       my $d = $1;
		       chomp($d);
		       $self->element({'Name' => 'Statistics_posted_date',
				       'Data' => $d});
		   } elsif( ! /^\s+$/ ) { 
		       #$self->debug( "unmatched stat $_");
		   }
               }
               $last = $_;
           }
       } elsif( $self->in_element('hsp') ) {
           #$self->debug("blast.pm: Processing HSP\n");
           # let's read 3 lines at a time;
	   # bl2seq hackiness... Not sure I like
	   $self->{'_reporttype'} ||= $DEFAULTREPORTTYPE;
           my %data = ( 'Query' => '',
                        'Mid' => '',
                        'Hit' => '' );
           my $len;
           for( my $i = 0; 
                defined($_) && $i < 3; 
                $i++ ) {
	       $self->debug("$i: $_") if $v; 
	       if( ($i == 0 && /^\s+$/ ) || 
		   /^\s*Lambda/i ) { 
		   $self->_pushback($_) if defined $_;
                   $self->end_element({'Name' => 'Hsp'});
                   last; 
               }
               chomp;
               if( /^((Query|Sbjct):\s+(\-?\d+)\s*)(\S+)\s+(\-?\d+)/ ) {
		   my ($full,$type,$start,$str,$end) = ($1,$2,$3,$4,$5);
		   if( $str eq '-' ) {
		       $i = 3 if $type eq 'Sbjct';
		   } else { 
		       $data{$type} = $str;
		   }
		   $len = length($full);
		   $self->{"\_$type"}->{'begin'} = $start unless $self->{"_$type"}->{'begin'};
                   $self->{"\_$type"}->{'end'} = $end;
               } else { 
		   $self->throw("no data for midline $_") 
                       unless (defined $_ && defined $len);
                   $data{'Mid'} = substr($_,$len);
               }
               $_ = $self->_readline();               
           }
           $self->characters({'Name' => 'Hsp_qseq',
                              'Data' => $data{'Query'} });
           $self->characters({'Name' => 'Hsp_hseq',
                              'Data' => $data{'Sbjct'}});
           $self->characters({'Name' => 'Hsp_midline',
                              'Data' => $data{'Mid'} });
       } else { 
           $self->debug( "blast.pm: unrecognized line $_");
       }
   } 
#   $self->debug("blast.pm: End of BlastOutput\n");
   if( $self->{'_seentop'} ) {
       $self->within_element('hsp') && 
	   $self->end_element({ 'Name' => 'Hsp'});
       $self->within_element('hit') && 
	   $self->end_element({ 'Name' => 'Hit'});
       $self->within_element('iteration') && 
	   $self->end_element({'Name' => 'Iteration'});
       if( $bl2seq_fix ) { 
	   $self->element({ 'Name' => 'BlastOutput_program',
			    'Data' => $reporttype});
       }    
       $self->end_element({'Name' => 'BlastOutput'});
   }
   return $self->end_document();
}

# Private method for internal use only.
sub _start_blastoutput {
   my $self = shift;
   $self->start_element({'Name' => 'BlastOutput'});
   $self->{'_seentop'} = 1;
   $self->{'_result_count'}++;
   $self->{'_handler_rc'} = undef;
}

sub _start_iteration {
   my $self = shift;
   $self->start_element({'Name' => 'Iteration'});
#   $self->{'_hit_info'} = undef;
}

=head2 _will_handle

 Title   : _will_handle
 Usage   : Private method. For internal use only.
              if( $self->_will_handle($type) ) { ... }
 Function: Provides an optimized way to check whether or not an element of a 
           given type is to be handled.
 Returns : Reference to EventHandler object if the element type is to be handled.
           undef if the element type is not to be handled.
 Args    : string containing type of element.

Optimizations:

=over 2

=item 1

Using the cached pointer to the EventHandler to minimize repeated
lookups.

=item 2

Caching the will_handle status for each type that is encountered so
that it only need be checked by calling
handler-E<gt>will_handle($type) once.

=back

This does not lead to a major savings by itself (only 5-10%).  In
combination with other optimizations, or for large parse jobs, the
savings good be significant.

To test against the unoptimized version, remove the parentheses from
around the third term in the ternary " ? : " operator and add two
calls to $self-E<gt>_eventHandler().

=cut

sub _will_handle {
    my ($self,$type) = @_;
    my $handler = $self->{'_handler_cache'};
    my $will_handle = defined($self->{'_will_handle_cache'}->{$type})
                             ? $self->{'_will_handle_cache'}->{$type}
                             : ($self->{'_will_handle_cache'}->{$type} =
                               $handler->will_handle($type));

    return $will_handle ? $handler : undef;
}


=head2 start_element

 Title   : start_element
 Usage   : $eventgenerator->start_element
 Function: Handles a start element event
 Returns : none
 Args    : hashref with at least 2 keys 'Data' and 'Name'

=cut

sub start_element{
   my ($self,$data) = @_;
   # we currently don't care about attributes
   my $nm = $data->{'Name'};
   my $type = $MODEMAP{$nm};
   if( $type ) {
       my $handler = $self->_will_handle($type);
       if( $handler ) {
           my $func = sprintf("start_%s",lc $type);
           $self->{'_handler_rc'} = $handler->$func($data->{'Attributes'});
       }
       else {
           $self->throw(-class=>'Bio::SearchIO::InternalParserError',
                        -text=>"Can't handle elements of type '$type'.",
                        -value=>$type);
       }
       unshift @{$self->{'_elements'}}, $type;
       if( $type eq 'result') {
           $self->{'_values'} = {};
           $self->{'_result'}= undef;
       } else { 
           # cleanup some things
           if( defined $self->{'_values'} ) {
               foreach my $k ( grep { /^\U$type\-/ } 
                               keys %{$self->{'_values'}} ) { 
                   delete $self->{'_values'}->{$k};
               }
           }
       }
   }
}

=head2 end_element

 Title   : start_element
 Usage   : $eventgenerator->end_element
 Function: Handles an end element event
 Returns : none
 Args    : hashref with at least 2 keys 'Data' and 'Name'


=cut

sub end_element {
    my ($self,$data) = @_;
    my $nm = $data->{'Name'};
    my $type = $MODEMAP{$nm};
    my $rc;
    if($nm eq 'BlastOutput_program') {
	if( $self->{'_last_data'} =~ /(t?blast[npx])/i ) {
	    $self->{'_reporttype'} = uc $1;
	}
	$self->{'_reporttype'} ||= $DEFAULTREPORTTYPE;
    }

    # Hsps are sort of weird, in that they end when another
    # object begins so have to detect this in end_element for now
    if( $nm eq 'Hsp' ) {
        foreach ( qw(Hsp_qseq Hsp_midline Hsp_hseq) ) {
            $self->element({'Name' => $_,
                            'Data' => $self->{'_last_hspdata'}->{$_}});
        }
        $self->{'_last_hspdata'} = {};
        $self->element({'Name' => 'Hsp_query-from',
                        'Data' => $self->{'_Query'}->{'begin'}});
        $self->element({'Name' => 'Hsp_query-to',
                        'Data' => $self->{'_Query'}->{'end'}});
        
        $self->element({'Name' => 'Hsp_hit-from',
                        'Data' => $self->{'_Sbjct'}->{'begin'}});
        $self->element({'Name' => 'Hsp_hit-to',
                        'Data' => $self->{'_Sbjct'}->{'end'}});
#    } elsif( $nm eq 'Iteration' ) {
# Nothing special needs to be done here.
    }
    if( $type = $MODEMAP{$nm} ) {
        my $handler = $self->_will_handle($type);
        if( $handler ) {
            my $func = sprintf("end_%s",lc $type);
            $rc = $handler->$func($self->{'_reporttype'},
                                  $self->{'_values'});
	} 
        shift @{$self->{'_elements'}};
	
    } elsif( $MAPPING{$nm} ) {         
        
        if ( ref($MAPPING{$nm}) =~ /hash/i ) {
            # this is where we shove in the data from the 
            # hashref info about params or statistics
            my $key = (keys %{$MAPPING{$nm}})[0];
            $self->{'_values'}->{$key}->{$MAPPING{$nm}->{$key}} = $self->{'_last_data'};
        } else {
            $self->{'_values'}->{$MAPPING{$nm}} = $self->{'_last_data'};
        }
    } else { 
        $self->debug( "blast.pm: unknown nm $nm, ignoring\n");
    }
    $self->{'_last_data'} = ''; # remove read data if we are at 
                                # end of an element
    $self->{'_result'} = $rc if( defined $type && $type eq 'result' );
    return $rc;    
}

=head2 element

 Title   : element
 Usage   : $eventhandler->element({'Name' => $name, 'Data' => $str});
 Function: Convenience method that calls start_element, characters, end_element
 Returns : none
 Args    : Hash ref with the keys 'Name' and 'Data'


=cut

sub element{
   my ($self,$data) = @_;
   $self->start_element($data);
   $self->characters($data);
   $self->end_element($data);
}

=head2 characters

 Title   : characters
 Usage   : $eventgenerator->characters($str)
 Function: Send a character events
 Returns : none
 Args    : string


=cut

sub characters{
   my ($self,$data) = @_;   
   if( $self->in_element('hsp') && 
       $data->{'Name'} =~ /^Hsp\_(qseq|hseq|midline)$/ ) {
       $self->{'_last_hspdata'}->{$data->{'Name'}} .= $data->{'Data'} if defined $data->{'Data'};
   } 
   return unless ( defined $data->{'Data'} && $data->{'Data'} !~ /^\s+$/ );
   $self->{'_last_data'} = $data->{'Data'}; 
}

=head2 within_element

 Title   : within_element
 Usage   : if( $eventgenerator->within_element($element) ) {}
 Function: Test if we are within a particular element
           This is different than 'in' because within can be tested
           for a whole block.
 Returns : boolean
 Args    : string element name 

See Also: L<in_element>

=cut

sub within_element{
   my ($self,$name) = @_;  
   return 0 if ( ! defined $name &&
                 ! defined  $self->{'_elements'} ||
                 scalar @{$self->{'_elements'}} == 0) ;
   foreach (  @{$self->{'_elements'}} ) {
       if( $_ eq $name  ) {
           return 1;
       } 
   }
   return 0;
}


=head2 in_element

 Title   : in_element
 Usage   : if( $eventgenerator->in_element($element) ) {}
 Function: Test if we are in a particular element
           This is different than 'within_element' because within
           can be tested for a whole block.
 Returns : boolean
 Args    : string element name 

See Also: L<within_element>

=cut

sub in_element{
   my ($self,$name) = @_;  
   return 0 if ! defined $self->{'_elements'}->[0];
   return ( $self->{'_elements'}->[0] eq $name)
}

=head2 start_document

 Title   : start_document
 Usage   : $eventgenerator->start_document
 Function: Handle a start document event
 Returns : none
 Args    : none


=cut

sub start_document{
    my ($self) = @_;
    $self->{'_lasttype'} = '';
    $self->{'_values'} = {};
    $self->{'_result'}= undef;
    $self->{'_elements'} = [];
}

=head2 end_document

 Title   : end_document
 Usage   : $eventgenerator->end_document
 Function: Handles an end document event
 Returns : Bio::Search::Result::ResultI object
 Args    : none


=cut

sub end_document{
   my ($self,@args) = @_;
#   $self->debug("blast.pm: end_document\n");
   return $self->{'_result'};
}


sub write_result {
   my ($self, $blast, @args) = @_;

   if( not defined($self->writer) ) {
       $self->warn("Writer not defined. Using a $DEFAULT_BLAST_WRITER_CLASS");
       $self->writer( $DEFAULT_BLAST_WRITER_CLASS->new() );
   }
   $self->SUPER::write_result( $blast, @args );
}

sub result_count {
    my $self = shift;
    return $self->{'_result_count'};
}

sub report_count { shift->result_count }


=head2 inclusion_threshold

 Title   : inclusion_threshold
 Usage   : my $incl_thresh = $isreb->inclusion_threshold;
         : $isreb->inclusion_threshold(1e-5);
 Function: Get/Set the e-value threshold for inclusion in the PSI-BLAST 
           score matrix model (blastpgp) that was used for generating the reports
           being parsed.
 Returns : number (real) 
           Default value: $Bio::SearchIO::IteratedSearchResultEventBuilder::DEFAULT_INCLUSION_THRESHOLD
 Args    : number (real)  (e.g., 0.0001 or 1e-4 )

=cut

# Delegates to the event handler. 
sub inclusion_threshold { shift->_eventHandler->inclusion_threshold(@_);
}

=head2 max_significance

 Usage     : $obj->max_significance();
 Purpose   : Set/Get the P or Expect value used as significance screening cutoff.
             This is the value of the -signif parameter supplied to new().
             Hits with P or E-value above this are skipped.
 Returns   : Scientific notation number with this format: 1.0e-05.
 Argument  : Scientific notation number or float (when setting)
 Comments  : Screening of significant hits uses the data provided on the
           : description line. For NCBI BLAST1 and WU-BLAST, this data 
           : is P-value. for NCBI BLAST2 it is an Expect value.

=cut

sub max_significance { shift->{'_handler_cache'}->max_significance(@_) }

=head2 signif

Synonym for L<max_significance()|max_significance>

=cut

sub signif { shift->max_significance(@_) }

=head2 min_score

 Usage     : $obj->min_score();
 Purpose   : Set/Get the Blast score used as screening cutoff.
             This is the value of the -score parameter supplied to new().
             Hits with scores below this are skipped.
 Returns   : Integer or scientific notation number.
 Argument  : Integer or scientific notation number (when setting)
 Comments  : Screening of significant hits uses the data provided on the
           : description line. 

=cut

sub min_score { shift->{'_handler_cache'}->max_significance(@_) }

=head2 min_query_length

 Usage     : $obj->min_query_length();
 Purpose   : Gets the query sequence length used as screening criteria.
             This is the value of the -min_query_len parameter supplied to new().
             Hits with sequence length below this are skipped.
 Returns   : Integer
 Argument  : n/a

=cut

sub min_query_length {
    my $self = shift;
    if (@_) {
        my $min_qlen = shift;
        if($min_qlen =~ /\D/ or $min_qlen <= 0) {
            $self->throw(-class =>'Bio::Root::BadParameter',
                         -text=>"Invalid minimum query length value: $min_qlen\n".
                                "Value must be an integer > 0. Value not set.",
                         -value=>$min_qlen);
        } 
        $self->{'_confirm_qlength'} = 1;
        $self->{'_min_query_length'} = $min_qlen;
    }

    return $self->{'_min_query_length'};
}

=head2 best_hit_only

 Title     : best_hit_only
 Usage     : print "only getting best hit.\n" if $obj->best_hit_only;
 Purpose   : Set/Get the indicator for whether or not to process only 
           : the best BlastHit.
 Returns   : Boolean (1 | 0)
 Argument  : Boolean (1 | 0) (when setting)

=cut

sub best_hit_only {
    my $self = shift;
    if(@_) { $self->{'_best'} = shift; }
    $self->{'_best'};
}

=head2 check_all_hits

 Title     : check_all_hits
 Usage     : print "checking all hits.\n" if $obj->check_all_hits;
 Purpose   : Set/Get the indicator for whether or not to process all hits.
           : If false, the parser will stop processing hits after the
           : the first non-significance hit or the first hit that fails 
           : any hit filter.
 Returns   : Boolean (1 | 0)
 Argument  : Boolean (1 | 0) (when setting)

=cut

sub check_all_hits {
    my $self = shift;
    if(@_) { $self->{'_check_all'} = shift; }
    $self->{'_check_all'};
}


=head2 _get_accession_version

 Title   : _get_accession_version
 Usage   : my ($acc,$ver) = &_get_accession_version($id)
 Function:Private function to get an accession,version pair
           for an ID (if it is in NCBI format)
 Returns : 2-pule of accession, version
 Args    : ID string to process


=cut

sub _get_accession_version {
    my $id = shift;

    # handle case when this is accidently called as a class method
    if( ref($id) && $id->isa('Bio::SearchIO') ) {
	$id = shift;
    }
    return undef unless defined $id;
    my ($acc, $version);
    if ($id =~ /(gb|emb|dbj|sp|pdb|bbs|ref|lcl)\|(.*)\|(.*)/) {
	($acc, $version) = split /\./, $2; 
    } elsif ($id =~ /(pir|prf|pat|gnl)\|(.*)\|(.*)/) {
	($acc, $version) = split /\./, $3;  
    } else {
	#punt, not matching the db's at ftp://ftp.ncbi.nih.gov/blast/db/README
	#Database Name                     Identifier Syntax
	#============================      ========================
	#GenBank                           gb|accession|locus
	#EMBL Data Library                 emb|accession|locus
	#DDBJ, DNA Database of Japan       dbj|accession|locus
	#NBRF PIR                          pir||entry
	#Protein Research Foundation       prf||name
	#SWISS-PROT                        sp|accession|entry name
	#Brookhaven Protein Data Bank      pdb|entry|chain
	#Patents                           pat|country|number 
	#GenInfo Backbone Id               bbs|number 
	#General database identifier           gnl|database|identifier
	#NCBI Reference Sequence           ref|accession|locus
	#Local Sequence identifier         lcl|identifier
	$acc=$id;
    }
    return ($acc,$version);
}

1;


__END__

Developer Notes
---------------

The following information is added in hopes of increasing the
maintainability of this code. It runs the risk of becoming obsolete as
the code gets updated. As always, double check against the actual
source. If you find any discrepencies, please correct them.
[ This documentation added on 3 Jun 2003. ]

The logic is the brainchild of Jason Stajich, documented by Steve
Chervitz. Jason: please check it over and modify as you see fit.

Question:
Elmo wants to know: How does this module unmarshall data from the input stream?
(i.e., how does information from a raw input file get added to 
the correct Bioperl object?)

Answer:

This answer is specific to SearchIO::blast, but may apply to other
SearchIO.pm subclasses as well. The following description gives the
basic idea. The actual processing is a little more complex for
certain types of data (HSP, Report Parameters).

You can think of blast::next_result() as faking a SAX XML parser,
making a non-XML document behave like its XML. The overhead to do this
is quite substantial (~650 lines of code instead of ~80 in
blastxml.pm).

0. First, add a key => value pair for the datum of interest to %MAPPING
    Example:
           'Foo_bar'   => 'Foo-bar',

1. next_result() collects the datum of interest from the input stream, 
   and calls element(). 
    Example:
            $self->element({ 'Name' => 'Foo_bar',
                             'Data' => $foobar});

2. The element() method is a convenience method that calls start_element(),
   characters(), and end_element(). 

3. start_element() checks to see if the event handler can handle a start_xxx(),
   where xxx = the 'Name' parameter passed into element(), and calls start_xxx()
   if so. Otherwise, start_element() does not do anything.

   Data that will have such an event handler are defined in %MODEMAP.
   Typically, there are only handler methods for the main parts of
   the search result (e.g., Result, Iteration, Hit, HSP),
   which have corresponding Bioperl modules. So in this example,
   there was an earlier call such as $self->element({'Name'=>'Foo'})
   and the Foo_bar datum is meant to ultimately go into a Foo object.

   The start_foo() method in the handler will typically do any
   data initialization necessary to prepare for creating a new Foo object.
   Example: SearchResultEventBuilder::start_result()

4. characters() takes the value of the 'Data' key from the hashref argument in
   the elements() call and saves it in a local data member:
   Example:
   $self->{'_last_data'} = $data->{'Data'};

5. end_element() is like start_element() in that it does the check for whether
   the event handler can handle end_xxx() and if so, calls it, passing in 
   the data collected from all of the characters() calls that occurred
   since the start_xxx() call.

   If there isn't any special handler for the data type specified by 'Name', 
   end_element() will place the data saved by characters() into another
   local data member that saves it in a hash with a key defined by %MAPPING.
   Example:
           $nm = $data->{'Name'};
           $self->{'_values'}->{$MAPPING{$nm}} = $self->{'_last_data'};

   In this case, $MAPPING{$nm} is 'Foo-bar'.

   end_element() finishes by resetting the local data member used by 
   characters(). (i.e., $self->{'_last_data'} = '';)

6. When the next_result() method encounters the end of the Foo element in the 
   input stream. It will invoke $self->end_element({'Name'=>'Foo'}).
   end_element() then sends all of the data in the $self->{'_values'} hash.
   Note that $self->{'_values'} is cleaned out during start_element(),
   keeping it at a resonable size.

   In the event handler, the end_foo() method takes the hash from end_element()
   and creates a new hash containing the same data, but having keys lacking
   the 'Foo' prefix (e.g., 'Foo-bar' becomes '-bar'). The handler's end_foo()
   method then creates the Foo object, passing in this new hash as an argument.
   Example: SearchResultEventBuilder::end_result()

7. Objects created from the data in the search result are managed by 
   the event handler which adds them to a ResultI object (using API methods
   for that object). The ResultI object gets passed back to
   SearchIO::end_element() when it calls end_result().

   The ResultI object is then saved in an internal data member of the 
   SearchIO object, which returns it at the end of next_result()
   by calling end_document().

   (Technical Note: All objects created by end_xxx() methods in the event 
    handler are returned to SearchIO::end_element(), but the SearchIO object
    only cares about the ResultI objects.)

(Sesame Street aficionados note: This answer was NOT given by Mr. Noodle ;-P)



