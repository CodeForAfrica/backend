use strict;
use warnings;

use Modern::Perl '2015';
use MediaWords::CommonLibs;

use Test::More;

use MediaWords::Solr::Dump;

# Unit tests for _import_achieved_replication(): the check that decides, from a Solr update
# response, whether a batch was replicated to enough shards to count as imported. This is the
# guard that keeps a silently-partial write (HTTP 200 but a shard stored nothing) from being
# dequeued and logged as imported. Pure function: no DB or Solr needed.

sub _check($$)
{
    my ( $response, $min_rf ) = @_;
    return MediaWords::Solr::Dump::_import_achieved_replication( $response, $min_rf );
}

# rf reported in responseHeader (Solr's usual shape)
ok( _check( '{"responseHeader":{"rf":2,"status":0}}', 2 ), 'rf == min_rf passes' );
ok( _check( '{"responseHeader":{"rf":3,"status":0}}', 2 ), 'rf > min_rf passes' );
ok( !_check( '{"responseHeader":{"rf":1,"status":0}}', 2 ), 'rf < min_rf fails' );

# the silent-loss case this fix targets: request succeeded but a shard stored zero replicas
ok( !_check( '{"responseHeader":{"rf":0,"status":0}}', 1 ), 'rf 0 with min_rf 1 fails (silent drop caught)' );
ok( _check( '{"responseHeader":{"rf":1,"status":0}}', 1 ), 'healthy single replica passes default min_rf 1' );

# rf reported at the top level (tolerated as a fallback shape)
ok( !_check( '{"rf":0,"responseHeader":{"status":0}}', 1 ), 'top-level rf is honoured' );

# check disabled -> always passes, regardless of response
ok( _check( '{"responseHeader":{"rf":0,"status":0}}', 0 ),     'min_rf 0 disables the check' );
ok( _check( '{"responseHeader":{"rf":0,"status":0}}', undef ), 'undef min_rf disables the check' );

# conservative fallbacks: never block importing on an unexpected response shape
ok( _check( '{"responseHeader":{"status":0}}', 1 ), 'missing rf assumes success (warns)' );
ok( _check( 'not json at all',                 1 ), 'unparseable response assumes success (warns)' );

done_testing();
