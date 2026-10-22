use strict;
use warnings;

use Modern::Perl '2015';
use MediaWords::CommonLibs;

use Test::More;

use MediaWords::DB;
use MediaWords::Solr;
use MediaWords::Solr::Dump;
use MediaWords::Test::Solr;
use MediaWords::Test::DB::Create;

sub _num_in_queue($$)
{
    my ( $db, $stories_id ) = @_;
    my ( $n ) = $db->query( "select count(*) from solr_import_stories where stories_id = ?", $stories_id )->flat;
    return $n;
}

sub _num_in_import_log($$)
{
    my ( $db, $stories_id ) = @_;
    my ( $n ) = $db->query( "select count(*) from solr_imported_stories where stories_id = ?", $stories_id )->flat;
    return $n;
}

sub _num_in_solr($$)
{
    my ( $db, $stories_id ) = @_;
    return MediaWords::Solr::get_solr_num_found( $db, { q => "stories_id:$stories_id" } );
}

# Regression test for the importer dropping stories it never sent to Solr.
#
# Each import cycle builds Solr documents only for stories that are ready (extracted,
# with story_sentences). Previously it then deleted the ENTIRE pulled batch from the
# queue and logged all of it as "imported", so a story that was queued but not yet
# extracted was removed and marked imported without ever being sent -> permanently lost.
#
# The fix deletes and logs only the stories actually sent; un-sent stories stay queued
# and are retried on a later cycle once they become sendable.
sub test_retry_unsent_stories($)
{
    my ( $db ) = @_;

    # set up a working Solr test index with a few fully-indexed stories
    MediaWords::Test::Solr::create_indexed_test_story_stack(
        $db,
        { medium_1 => { feed_1 => [ map { "story_$_" } ( 1 .. 3 ) ] } }
    );

    # create a fresh raw story that is NOT extracted: it has no story_sentences, so the
    # importer cannot build a Solr document for it (it is "un-sendable" this cycle).
    my $medium = MediaWords::Test::DB::Create::create_test_medium( $db, 'unsent' );
    my $feed   = MediaWords::Test::DB::Create::create_test_feed( $db, 'unsent', $medium );
    my $story  = MediaWords::Test::DB::Create::create_test_story( $db, 'unsent', $feed );
    my $stories_id = $story->{ stories_id };

    # a not-yet-extracted story is freshly collected; keep collect_date recent so it is
    # treated as in-flight (retry) rather than a permanently-unsendable story to drop.
    $db->query( "update stories set collect_date = now() where stories_id = ?", $stories_id );

    # mark it processed so it gets queued for import (a processed_stories insert queues the
    # story), but it still has no sentences, so it cannot be sent yet.
    $db->create( 'processed_stories', { stories_id => $stories_id } );
    $db->commit();

    is( _num_in_queue( $db, $stories_id ), 1, 'un-sendable story is queued for import' );

    my $solr_before = MediaWords::Solr::get_solr_num_found( $db, { q => '*:*' } );

    # run a one-shot import; the un-sendable story cannot be built or sent
    MediaWords::Solr::Dump::import_data( $db, { empty_queue => 1, throttle => 0 } );

    # THE FIX: an un-sent story must stay queued, must NOT be logged as imported, and must
    # NOT appear in Solr. (Before the fix it was deleted, logged as imported, and lost.)
    is( _num_in_queue( $db, $stories_id ),      1, 'un-sent story stays queued for retry' );
    is( _num_in_import_log( $db, $stories_id ), 0, 'un-sent story is not logged as imported' );
    is( _num_in_solr( $db, $stories_id ),       0, 'un-sent story is not in Solr' );
    is( MediaWords::Solr::get_solr_num_found( $db, { q => '*:*' } ),
        $solr_before, 'total Solr count unchanged by the un-sendable story' );

    # make the story sendable by adding a sentence, then re-run the import
    $db->query( <<SQL, $stories_id, $medium->{ media_id } );
insert into story_sentences ( stories_id, sentence_number, sentence, media_id )
    values ( ?, 1, 'This is a test sentence for the retried story.', ? )
SQL
    $db->commit();

    MediaWords::Solr::Dump::import_data( $db, { empty_queue => 1, throttle => 0 } );

    # once sendable, the retried story is sent, dequeued, logged, and searchable
    is( _num_in_queue( $db, $stories_id ),      0, 'story dequeued once sent' );
    is( _num_in_import_log( $db, $stories_id ), 1, 'story logged as imported once sent' );
    is( _num_in_solr( $db, $stories_id ),       1, 'story present in Solr once sent' );
}

# Regression test for the companion problem: a story that can NEVER be sent (processed,
# but no story_sentences -- e.g. every sentence removed as a per-week duplicate) must not
# linger in the queue forever. If it did, the daemon would re-pull and re-attempt it every
# cycle and the queue would grow without bound. Such a story (once its extraction is long
# finished, enforced by a collect_date age gate) must be dead-lettered: removed from the
# queue, never logged as imported, never in Solr.
sub test_dead_letter_unsendable_stories($)
{
    my ( $db ) = @_;

    MediaWords::Test::Solr::create_indexed_test_story_stack(
        $db,
        { medium_dl => { feed_dl => [ map { "story_dl_$_" } ( 1 .. 3 ) ] } }
    );

    my $medium = MediaWords::Test::DB::Create::create_test_medium( $db, 'deadletter' );
    my $feed   = MediaWords::Test::DB::Create::create_test_feed( $db, 'deadletter', $medium );
    my $story  = MediaWords::Test::DB::Create::create_test_story( $db, 'deadletter', $feed );
    my $stories_id = $story->{ stories_id };

    # make the story old enough that its extraction is definitely finished, so a lack of
    # sentences means it is permanently unsendable (not merely mid-flight this cycle).
    $db->query( "update stories set collect_date = now() - interval '2 days' where stories_id = ?", $stories_id );

    # mark it processed (queues it) but leave it with no story_sentences
    $db->create( 'processed_stories', { stories_id => $stories_id } );
    $db->commit();

    is( _num_in_queue( $db, $stories_id ), 1, 'permanently-unsendable story is queued' );

    my $solr_before = MediaWords::Solr::get_solr_num_found( $db, { q => '*:*' } );

    MediaWords::Solr::Dump::import_data( $db, { empty_queue => 1, throttle => 0 } );

    is( _num_in_queue( $db, $stories_id ),      0, 'permanently-unsendable story is dead-lettered (removed from queue)' );
    is( _num_in_import_log( $db, $stories_id ), 0, 'dead-lettered story is not logged as imported' );
    is( _num_in_solr( $db, $stories_id ),       0, 'dead-lettered story is not in Solr' );
    is( MediaWords::Solr::get_solr_num_found( $db, { q => '*:*' } ),
        $solr_before, 'total Solr count unchanged by the dead-lettered story' );
}

sub main
{
    my $db = MediaWords::DB::connect_to_db();

    test_retry_unsent_stories( $db );
    test_dead_letter_unsendable_stories( $db );

    done_testing();
}

main();
