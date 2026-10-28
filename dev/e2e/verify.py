#!/usr/bin/env python3
"""Run inside webapp-api; refuses every database except the isolated fixture."""
import json
import time
import uuid
import sys
import threading
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.request import Request, urlopen
from urllib.parse import urlencode
from urllib.error import HTTPError
from mediawords.db import connect_to_db
from mediawords.test.db.create import create_test_medium, create_test_story, create_download_for_story
from webapp.auth.user import NewUser
from webapp.auth.register import add_user
from webapp.auth.info import user_info


def main():
    db = connect_to_db()
    if db.query('SELECT current_database() AS name').hash()['name'] != 'civicsignal_e2e':
        raise RuntimeError('Refusing to test against a non-fixture database')
    if '--search' in sys.argv:
        with open('/tmp/civicsignal-e2e-story.json') as source:
            state = json.load(source)
        key = user_info(db, state['label'] + '@example.invalid').global_api_key()
        target = 'http://webapp-httpd/api/v2/stories/list?' + urlencode({'q': 'stories_id:' + str(state['stories_id']), 'key': key})
        try:
            with urlopen(target, timeout=30) as response:
                results = json.load(response)
        except HTTPError as error:
            raise AssertionError('Search returned HTTP {}'.format(error.code)) from None
        assert any(int(row['stories_id']) == state['stories_id'] for row in results), 'Indexed story missing from API search'
        print('PASS Solr indexing and HTTP story search', flush=True)
        return
    label = 'civicsignal-e2e-' + uuid.uuid4().hex[:12]
    email = label + '@example.invalid'
    password = 'LocalTestPassword-' + uuid.uuid4().hex
    role = db.query("SELECT auth_roles_id FROM auth_roles WHERE role='admin'").hash()['auth_roles_id']
    add_user(db, NewUser(email=email,full_name=label,notes='',active=True,has_consented=True,password=password,password_repeat=password,role_ids=[role]))
    key = user_info(db,email).global_api_key()

    def request(path, method='GET', data=None, parameters=None):
        parameters = dict(parameters or {}, key=key)
        target = 'http://webapp-httpd' + path + '?' + urlencode(parameters)
        body = json.dumps(data).encode() if data is not None else None
        req = Request(target,data=body,method=method,headers={'Content-Type':'application/json'})
        try:
            with urlopen(req,timeout=30) as response:
                assert response.status == 200, 'Unexpected HTTP status'
                return json.load(response)
        except HTTPError as error:
            raise AssertionError('{} {} returned HTTP {}'.format(method,path,error.code)) from None

    login = request('/api/v2/auth/login','POST',{'email':email,'password':password})
    assert login['success'] and login['profile']['email'] == email
    print('PASS HTTP authentication and profile',flush=True)
    medium = create_test_medium(db,label)
    feed = request('/api/v2/feeds/create','POST',{'media_id':medium['media_id'],'name':label,'url':'http://example.invalid/feed','type':'syndicated','active':False})['feed']
    updated = request('/api/v2/feeds/update','PUT',{'feeds_id':feed['feeds_id'],'name':label+' updated','url':feed['url'],'type':'syndicated','active':False})['feed']
    assert updated['name'] == label+' updated'
    fetched = request('/api/v2/feeds/list',parameters={'media_id':medium['media_id']})
    assert any(item['feeds_id']==feed['feeds_id'] for item in fetched)
    print('PASS HTTP feed create/update/list and PostgreSQL persistence',flush=True)

    story = create_test_story(db,label,feed)
    db.update_by_id('stories',story['stories_id'],{'full_text_rss':False})
    download = create_download_for_story(db,feed,story)
    article = '<html><title>CivicSignal local verification</title><body><article>' + ('<p>Community journalists report on education, health, public policy and local government. Citizens discussed transparent public services and independent reporting during the meeting. This verification article contains original English sentences for the extraction and search pipeline.</p>'*5) + '</article></body></html>'
    class ArticleHandler(BaseHTTPRequestHandler):
        def do_GET(self):
            content = article.encode()
            self.send_response(200)
            self.send_header('Content-Type', 'text/html; charset=utf-8')
            self.send_header('Content-Length', str(len(content)))
            self.end_headers()
            self.wfile.write(content)
        def log_message(self, *args):
            pass
    server = HTTPServer(('0.0.0.0', 18080), ArticleHandler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    url = 'http://webapp-api:18080/' + label
    db.update_by_id('stories', story['stories_id'], {'url': url})
    db.update_by_id('downloads', download['downloads_id'], {'url': url, 'host': 'webapp-api', 'state': 'pending', 'path': None, 'download_time': 'NOW()'})
    deadline = time.monotonic() + 180
    while time.monotonic() < deadline:
        if db.query('SELECT 1 AS found FROM processed_stories WHERE stories_id=%(id)s',{'id':story['stories_id']}).hash():
            break
        time.sleep(1)
    else:
        raise AssertionError('Story did not complete CLIFF/NYT annotation')
    server.shutdown()
    fetched_download = db.find_by_id('downloads', download['downloads_id'])
    assert fetched_download['state'] == 'success', 'Crawler did not fetch article'
    assert db.query('SELECT 1 AS found FROM story_sentences WHERE stories_id=%(id)s LIMIT 1',{'id':story['stories_id']}).hash(), 'No extracted sentences'
    print('PASS HTTP crawling, RabbitMQ extraction, CLIFF/NYT annotation and processed story sentences',flush=True)
    state = {'stories_id':story['stories_id'],'media_id':medium['media_id'],'label':label}
    with open('/tmp/civicsignal-e2e-story.json','w') as target:
        json.dump(state,target)
    print('Fixture story ID:',story['stories_id'],flush=True)


if __name__ == '__main__':
    main()
