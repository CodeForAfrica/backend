package MediaWords::DBI::Stats;

#
# Various functions related to the stats table
#

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

# live row estimate for a table plus every partition / inheritance child under it
sub _estimated_rows($$)
{
    my ( $db, $table ) = @_;

    my ( $rows ) = $db->query( <<SQL, $table )->flat;
with recursive tree ( oid ) as (
    select \$1::regclass::oid
    union all
    select i.inhrelid from pg_inherits i join tree on ( i.inhparent = tree.oid )
)
select coalesce( sum( s.n_live_tup ), 0 )::bigint
    from tree join pg_stat_user_tables s on ( s.relid = tree.oid )
SQL

    return $rows;
}

# update the data in the mediacloud_stats data to reflect the state of the systems (total stories, downloads, etc).
sub refresh_stats($)
{
    my ( $db ) = @_;

    my $stats = {};

    ( $stats->{ daily_downloads } ) = $db->query( <<SQL )->flat;
select count(*) as daily_downloads
    from downloads_in_past_day
SQL

    ( $stats->{ daily_stories } ) = $db->query( <<SQL )->flat;
select count(*) as daily_stories
    from stories_collected_in_past_day
SQL

    # Row estimates summed over the table and all its partitions. reltuples on the parent was wrong:
    # it is 0 for partitioned tables (downloads, story_sentences_p) and only refreshed by (auto)analyze
    # on stories, so it froze for months. n_live_tup is kept current by the stats collector.
    # ponytail: estimate, resets to ~0 after pg_stat_reset() or crash recovery until autovacuum catches up
    $stats->{ total_stories }   = _estimated_rows( $db, 'public.stories' );
    $stats->{ total_downloads } = _estimated_rows( $db, 'public.downloads' );
    $stats->{ total_sentences } = _estimated_rows( $db, 'public.story_sentences_p' );

    ( $stats->{ active_crawled_feeds } ) = $db->query( <<SQL )->flat;
select count(*) active_crawled_feeds
    from feeds f
    where
        f.type = 'syndicated' and
        f.last_new_story_time > now() - '180 days'::interval
SQL

    ( $stats->{ active_crawled_media } ) = $db->query( <<SQL )->flat;
select count(*) active_crawled_media
    from media m
    where
        media_id in (
            select media_id
                from feeds f
                where
                    f.type = 'syndicated' and
                    f.last_new_story_time > now() - '180 days'::interval
        )
SQL

    $db->begin;

    $db->query( "delete from mediacloud_stats" );

    $db->insert( 'mediacloud_stats', $stats );

    $db->commit;
}

1;
