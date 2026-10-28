from mediawords.db import connect_to_db
from mediawords.test.db.create import create_test_medium, create_test_feed
from crawler_provider import provide_download_ids, _pending_download_ids


def test_provide_download_ids() -> None:
    db = connect_to_db()

    medium = create_test_medium(db, 'foo')
    feed = create_test_feed(db, 'foo', medium=medium)

    hosts = ('foo.bar', 'bar.bat', 'bat.baz')
    downloads_per_host = 3

    for host in hosts:
        for i in range(downloads_per_host):
            download = {
                'feeds_id': feed['feeds_id'],
                'state': 'pending',
                'priority': 1,
                'sequence': 1,
                'type': 'content',
                'url': 'http://' + host + '/' + str(i),
                'host': host}

            db.create('downloads', download)

    download_ids = provide_download_ids(db)

    # +1 for the test feed
    assert len(download_ids) == len(hosts) + 1


def test_pending_download_ids_without_newer_database_function() -> None:
    db = connect_to_db()
    db.begin()
    try:
        # Reproduce the existing database's missing function without migrating it.
        db.query("DROP FUNCTION IF EXISTS get_downloads_for_queue()")
        medium = create_test_medium(db, 'queue-compatibility')
        feed = create_test_feed(db, 'queue-compatibility', medium=medium)
        downloads = []
        for host, priority in [('compat-a.example', 0), ('compat-a.example', 1),
                               ('compat-a.example', 1), ('compat-a.example', 2),
                               ('compat-b.example', 1), ('compat-b.example', 1)]:
            downloads.append(db.create('downloads', {
                'feeds_id': feed['feeds_id'], 'state': 'pending', 'priority': priority,
                'sequence': 1, 'type': 'content', 'host': host,
                'url': 'https://' + host + '/' + str(len(downloads)),
            })['downloads_id'])
        db.create('queued_downloads', {'downloads_id': downloads[0]})
        selected = set(_pending_download_ids(db))
        # One per host, skip already queued, then prefer priority and newest ID.
        assert selected.intersection(downloads) == {downloads[2], downloads[5]}
    finally:
        db.rollback()
