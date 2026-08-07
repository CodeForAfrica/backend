import pytest

from mediawords.util.config.common import (
    _authenticated_domains_from_json,
    AuthenticatedDomain,
    DatabaseConfig,
    McConfigAuthenticatedDomainsException,
    RabbitMQConfig,
    CommonConfig,
)


def test_database_config_defaults_to_local_compose_values(monkeypatch):
    monkeypatch.delenv('MC_DATABASE_URL', raising=False)
    assert DatabaseConfig.hostname() == "postgresql-pgbouncer"
    assert DatabaseConfig.port() == 6432
    assert DatabaseConfig.database_name() == "mediacloud"
    assert DatabaseConfig.username() == "mediacloud"
    assert DatabaseConfig.password() == "mediacloud"


def test_database_config_reads_mc_database_url(monkeypatch):
    monkeypatch.setenv('MC_DATABASE_URL', "postgresql://someuser:somepass@example.com:5432/somedb")
    assert DatabaseConfig.hostname() == "example.com"
    assert DatabaseConfig.port() == 5432
    assert DatabaseConfig.database_name() == "somedb"
    assert DatabaseConfig.username() == "someuser"
    assert DatabaseConfig.password() == "somepass"


def test_rabbitmq_config_defaults_to_local_compose_values(monkeypatch):
    monkeypatch.delenv('MC_RABBITMQ_URL', raising=False)
    assert RabbitMQConfig.hostname() == "rabbitmq-server"
    assert RabbitMQConfig.port() == 5672
    assert RabbitMQConfig.username() == "mediacloud"
    assert RabbitMQConfig.password() == "mediacloud"
    assert RabbitMQConfig.vhost() == "/mediacloud"


def test_rabbitmq_config_reads_mc_rabbitmq_url(monkeypatch):
    monkeypatch.setenv('MC_RABBITMQ_URL', "amqp://someuser:somepass@example.com:5673//mediacloud")
    assert RabbitMQConfig.hostname() == "example.com"
    assert RabbitMQConfig.port() == 5673
    assert RabbitMQConfig.username() == "someuser"
    assert RabbitMQConfig.password() == "somepass"
    assert RabbitMQConfig.vhost() == "/mediacloud"


def test_solr_and_extractor_urls_default_and_override(monkeypatch):
    monkeypatch.delenv('MC_SOLR_URL', raising=False)
    monkeypatch.delenv('MC_EXTRACTOR_API_URL', raising=False)
    assert CommonConfig.solr_url() == "http://solr-shard-01:8983/solr"
    assert CommonConfig.extractor_api_url() == "http://extract-article-from-page:8080/extract"

    monkeypatch.setenv('MC_SOLR_URL', "http://solr.internal.example.com:8983/solr/")
    monkeypatch.setenv('MC_EXTRACTOR_API_URL', "http://extractor.internal.example.com:8080/extract")
    assert CommonConfig.solr_url() == "http://solr.internal.example.com:8983/solr"
    assert CommonConfig.extractor_api_url() == "http://extractor.internal.example.com:8080/extract"


def test_authenticated_domains_from_json():
    # noinspection PyTypeChecker
    assert _authenticated_domains_from_json(None) == []
    assert _authenticated_domains_from_json('') == []
    assert _authenticated_domains_from_json('  ') == []

    assert _authenticated_domains_from_json("""
        [
            {"domain": "domain", "username": "user", "password": "pass"}
        ]
    """) == [
        AuthenticatedDomain(domain='domain', username='user', password='pass'),
    ]
    assert _authenticated_domains_from_json("""
        [
            {"domain": "domain", "username": "user", "password": "pass"},
            {"domain": "domain2", "username": "user2", "password": "pass2"}
        ]
    """) == [
        AuthenticatedDomain(domain='domain', username='user', password='pass'),
        AuthenticatedDomain(domain='domain2', username='user2', password='pass2'),
    ]

    with pytest.raises(McConfigAuthenticatedDomainsException):
        # Invalid JSON
        _authenticated_domains_from_json('blergh')

    with pytest.raises(McConfigAuthenticatedDomainsException):
        # No domain
        _authenticated_domains_from_json("""
            [
                {"username": "user", "password": "pass"}
            ]
        """)

    with pytest.raises(McConfigAuthenticatedDomainsException):
        # No password
        _authenticated_domains_from_json("""
            [
                {"domain": "domain", "username": "user"}
            ]
        """)

    with pytest.raises(McConfigAuthenticatedDomainsException):
        # List within a list
        _authenticated_domains_from_json("""
            [
                [
                    {"domain": "domain", "username": "user", "password": "pass"}
                ]
            ]
        """)

    with pytest.raises(McConfigAuthenticatedDomainsException):
        # Just a dictionary without a list
        _authenticated_domains_from_json("""
            {"domain": "domain", "username": "user", "password": "pass"}
        """)

    with pytest.raises(McConfigAuthenticatedDomainsException):
        # Single quotes instead of double ones (invalid JSON)
        _authenticated_domains_from_json("""
            [
                {'domain': 'domain', 'username': 'user', 'password': 'pass'}
            ]
        """)
