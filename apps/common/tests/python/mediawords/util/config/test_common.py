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


def test_existing_database_url_decodes_credentials_and_defaults_to_postgres_port(monkeypatch):
    monkeypatch.setenv('MC_DATABASE_URL', 'postgresql://user%40domain:p%40ss%2Fword@example.com/app%2Ddb?sslmode=require&connect_timeout=5')
    assert DatabaseConfig.username() == 'user@domain'
    assert DatabaseConfig.password() == 'p@ss/word'
    assert DatabaseConfig.database_name() == 'app-db'
    assert DatabaseConfig.port() == 5432
    assert DatabaseConfig.connection_options() == {'sslmode': 'require', 'connect_timeout': '5'}


def test_invalid_existing_database_url_is_rejected(monkeypatch):
    from mediawords.util.config import McConfigException
    monkeypatch.setenv('MC_DATABASE_URL', 'https://example.com/db')
    with pytest.raises(McConfigException):
        DatabaseConfig.hostname()
    monkeypatch.setenv('MC_DATABASE_URL', 'postgresql://user:password@db/app?password=wrong')
    with pytest.raises(McConfigException):
        DatabaseConfig.connection_options()


def test_rabbitmq_sidecar_credentials_override_url_defaults(monkeypatch):
    monkeypatch.setenv('MC_RABBITMQ_HOST', 'localhost')
    monkeypatch.setenv('MC_RABBITMQ_PASSWORD', 'secret')
    assert RabbitMQConfig.hostname() == 'localhost'
    assert RabbitMQConfig.password() == 'secret'


def test_external_smtp_configuration(monkeypatch):
    from mediawords.util.config.common import SMTPConfig
    monkeypatch.setenv('MC_SMTP_HOST', 'mail.example.org')
    monkeypatch.setenv('MC_SMTP_PORT', '587')
    monkeypatch.setenv('MC_SMTP_STARTTLS', '1')
    monkeypatch.setenv('MC_SMTP_USERNAME', 'mailer')
    monkeypatch.setenv('MC_SMTP_PASSWORD', 'secret')
    assert SMTPConfig.hostname() == 'mail.example.org'
    assert SMTPConfig.port() == 587
    assert SMTPConfig.use_starttls()
    assert SMTPConfig.username() == 'mailer'
    assert SMTPConfig.password() == 'secret'


def test_worker_connection_urls_preserve_ssl_and_escape_credentials(monkeypatch):
    monkeypatch.setenv('MC_DATABASE_URL', 'postgresql://user%40domain:p%40ss%2Fword@example.com/app?sslmode=require')
    assert DatabaseConfig.connection_url('db+postgresql+psycopg2') == 'db+postgresql+psycopg2://user%40domain:p%40ss%2Fword@example.com:5432/app?sslmode=require'
    monkeypatch.setenv('MC_RABBITMQ_HOST', 'localhost')
    monkeypatch.setenv('MC_RABBITMQ_PASSWORD', 'p@ss/word')
    assert RabbitMQConfig.connection_url() == 'amqp://mediacloud:p%40ss%2Fword@localhost:5672/%2Fmediacloud'
