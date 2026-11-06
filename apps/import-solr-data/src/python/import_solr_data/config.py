from mediawords.util.config import env_value


class SolrImportConfig(object):
    """Solr story import script configuration."""

    @staticmethod
    def max_queued_stories() -> int:
        """Number of stories to import in one go."""
        return int(env_value('MC_SOLR_IMPORT_MAX_QUEUED_STORIES'))

    @staticmethod
    def min_replication_factor() -> int:
        """Minimum Solr replication factor required for an import batch to count as imported.

        Sent to Solr as the `min_rf` update parameter. Solr then reports the achieved
        replication factor (`rf`) in the update response; if `rf` is lower than this, the
        batch is treated as not imported, so the stories stay queued and are retried instead
        of being silently marked imported and lost.

        Defaults to 1, which detects a shard that stored zero replicas (the silent-loss case)
        without changing behaviour on a healthy single-replica shard. Raise to 2+ once each
        shard has a healthy additional replica to require redundant storage.
        """
        value = env_value('MC_SOLR_IMPORT_MIN_REPLICATION_FACTOR', required=False)
        return int(value) if value else 1
