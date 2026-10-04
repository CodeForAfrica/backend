# syntax=docker/dockerfile:1
# Migration dependency snapshots: preserve installed Perl/Python libraries,
# but always ship common code and component code from this checkout.
# The old per-app Dockerfiles require unavailable gcr.io/mcback bases.
ARG CIVICSIGNAL_COMPONENT=webapp-api

FROM codeforafrica/cs-webapp-api:release@sha256:c4bc8e593474db1d969f76bda390d1e5770c722b337873906aab2f6831b0bd06 AS webapp-api
USER root
COPY apps/common/src/ /opt/mediacloud/src/common/
COPY apps/webapp-api/src/ /opt/mediacloud/src/webapp-api/
COPY apps/webapp-api/bin/ /opt/mediacloud/bin/
COPY apps/base/bin/container_memory_limit.sh apps/base/bin/container_cpu_limit.sh /
USER mediacloud

FROM codeforafrica/cs-crawler-provider:release@sha256:a9d8496d94a87ab1a161cf269af5f82b788dcc753a0c28f18c378e9fbff2ff77 AS crawler-provider
USER root
COPY apps/common/src/ /opt/mediacloud/src/common/
COPY apps/crawler-provider/src/ /opt/mediacloud/src/crawler-provider/
COPY apps/crawler-provider/bin/ /opt/mediacloud/bin/
COPY apps/base/bin/container_memory_limit.sh apps/base/bin/container_cpu_limit.sh /
USER mediacloud

FROM codeforafrica/cs-crawler-fetcher:release@sha256:14ec3187504e51b6afe1da6b87e53826bbc744854878675f3742dac6aaf4f262 AS crawler-fetcher
USER root
COPY apps/common/src/ /opt/mediacloud/src/common/
COPY apps/crawler-fetcher/src/ /opt/mediacloud/src/crawler-fetcher/
COPY apps/crawler-fetcher/bin/ /opt/mediacloud/bin/
COPY apps/base/bin/container_memory_limit.sh apps/base/bin/container_cpu_limit.sh /
USER mediacloud

FROM codeforafrica/cs-extract-article-from-page:release@sha256:2627e117f2adf2d78e210989877877a14ee0a5c0ca87687cfe590932e0265bb7 AS extract-article-from-page
USER root
COPY apps/common/src/ /opt/mediacloud/src/common/
COPY apps/extract-article-from-page/src/ /opt/mediacloud/src/extract-article-from-page/
COPY apps/extract-article-from-page/bin/ /opt/mediacloud/bin/
COPY apps/base/bin/container_memory_limit.sh apps/base/bin/container_cpu_limit.sh /
USER mediacloud

FROM codeforafrica/cs-extract-and-vector:release@sha256:0596e85490d86e94495d7ed3eb98ead94d41788d2cd52208e20d42ec8d957ceb AS extract-and-vector
USER root
COPY apps/common/src/ /opt/mediacloud/src/common/
COPY apps/extract-and-vector/src/ /opt/mediacloud/src/extract-and-vector/
COPY apps/extract-and-vector/bin/ /opt/mediacloud/bin/
COPY apps/base/bin/container_memory_limit.sh apps/base/bin/container_cpu_limit.sh /
USER mediacloud

FROM codeforafrica/cs-import-solr-data:release@sha256:c5833025faf1391499a850483d13fa873cc91e1a3dfe826e13ef9adafbaae066 AS import-solr-data
USER root
COPY apps/common/src/ /opt/mediacloud/src/common/
COPY apps/import-solr-data/src/ /opt/mediacloud/src/import-solr-data/
COPY apps/import-solr-data/bin/ /opt/mediacloud/bin/
COPY apps/base/bin/container_memory_limit.sh apps/base/bin/container_cpu_limit.sh /
USER mediacloud

FROM codeforafrica/cs-rescrape-media:release@sha256:00ddbfe4aef13afcbc09fcac2d45d133c08646ae954a7e20e3daab62a87cf742 AS rescrape-media
USER root
COPY apps/common/src/ /opt/mediacloud/src/common/
COPY apps/rescrape-media/src/ /opt/mediacloud/src/rescrape-media/
COPY apps/rescrape-media/bin/ /opt/mediacloud/bin/
COPY apps/base/bin/container_memory_limit.sh apps/base/bin/container_cpu_limit.sh /
USER mediacloud

FROM codeforafrica/cs-solr-zookeeper:release@sha256:e895c2d965e9537d47d4ae0558f009ae119201a51d91e28fd409df438f558739 AS solr-zookeeper
USER root
COPY apps/solr-base/src/solr/ /usr/src/solr/
COPY apps/solr-zookeeper/conf/ /opt/zookeeper/conf/
COPY apps/solr-zookeeper/bin/init_solr_config.sh apps/solr-zookeeper/bin/zookeeper.sh /
RUN rm -rf /var/lib/zookeeper-template/* && /init_solr_config.sh && mv /var/lib/zookeeper/* /var/lib/zookeeper-template/ && chown -R solr:solr /var/lib/zookeeper /var/lib/zookeeper-template && mkdir -p /state && chmod 0777 /state && sed -i 's@dataDir=/var/lib/zookeeper@dataDir=/state/zookeeper@' /opt/zookeeper/conf/zoo.cfg
ENV MC_ZOOKEEPER_DATA_DIR=/state/zookeeper
USER solr

FROM codeforafrica/cs-solr-shard:release@sha256:105a7fad70604f2c17279b38e97b208cdc256024940adebf5a890599e69b05f2 AS solr-shard-01
USER root
COPY apps/solr-base/src/solr/ /usr/src/solr/
COPY apps/solr-shard/resources/log4j.properties /var/lib/solr/resources/log4j.properties
COPY apps/solr-shard/bin/solr-shard.sh /solr-shard.sh
COPY apps/base/bin/container_memory_limit.sh /container_memory_limit.sh
COPY docker/solr-entrypoint.sh /civicsignal-solr-entrypoint.sh
# Keep an image-owned seed; Docker does not populate empty ECS EFS mounts.
RUN mkdir -p /state && chmod 0777 /state && cp -a /var/lib/solr /solr-template && cp -a /usr/src/solr/. /solr-template/
USER solr
ENTRYPOINT ["/civicsignal-solr-entrypoint.sh"]
CMD ["/solr-shard.sh"]

FROM codeforafrica/cs-webapp-httpd:release@sha256:83f282ac4515d87aada1dc6c24b07a756eed6b05d7993c48a1b97369258b6035 AS webapp-httpd
USER root
COPY apps/webapp-httpd/nginx/include/webapp-httpd.conf /etc/nginx/include/webapp-httpd.conf.template
COPY docker/httpd-entrypoint.sh /civicsignal-httpd-entrypoint.sh
ENTRYPOINT ["/civicsignal-httpd-entrypoint.sh"]
CMD ["nginx"]

FROM rabbitmq:4.2-alpine@sha256:d5d8797191db5828a2a2a3dabf295d2b558ae81e215e6c6cba26d567ae8fb236 AS rabbitmq-server
ENV RABBITMQ_NODENAME=rabbit@localhost RABBITMQ_MNESIA_BASE=/state/rabbitmq HOME=/tmp/rabbitmq
COPY docker/rabbitmq-entrypoint.sh /civicsignal-rabbitmq-entrypoint.sh
# Match the shared EFS access point identity, rather than chowning EFS as root.
RUN mkdir -p /state && chmod 0777 /state
USER 1000:1000
ENTRYPOINT ["/civicsignal-rabbitmq-entrypoint.sh"]
CMD ["rabbitmq-server"]

FROM codeforafrica/cs-cron-generate-daily-rss-dumps:release@sha256:d9d473a15815c17036ead2c2612fba8176e6b8166891994008368490ff5eabe3 AS maintenance
USER root
# Replace the inherited schedule; never run the same RSS job twice.
RUN rm -f /etc/cron.d/generate_daily_rss_dumps
COPY apps/common/src/ /opt/mediacloud/src/common/
COPY apps/base/bin/container_memory_limit.sh apps/base/bin/container_cpu_limit.sh /
COPY apps/cron-generate-daily-rss-dumps/src/ /opt/mediacloud/src/cron-generate-daily-rss-dumps/
COPY apps/cron-generate-daily-rss-dumps/bin/ /opt/mediacloud/bin/
COPY apps/cron-generate-daily-rss-dumps/crontab /etc/cron.d/cron-generate-daily-rss-dumps
COPY apps/cron-generate-media-health/src/ /opt/mediacloud/src/cron-generate-media-health/
COPY apps/cron-generate-media-health/bin/ /opt/mediacloud/bin/
COPY apps/cron-generate-media-health/crontab /etc/cron.d/cron-generate-media-health
COPY apps/cron-generate-user-summary/bin/ /opt/mediacloud/bin/
COPY apps/cron-generate-user-summary/crontab /etc/cron.d/cron-generate-user-summary
COPY apps/cron-print-long-running-job-states/bin/ /opt/mediacloud/bin/
COPY apps/cron-print-long-running-job-states/crontab /etc/cron.d/cron-print-long-running-job-states
COPY apps/cron-refresh-stats/bin/ /opt/mediacloud/bin/
COPY apps/cron-refresh-stats/crontab /etc/cron.d/cron-refresh-stats
COPY apps/cron-rescrape-due-media/bin/ /opt/mediacloud/bin/
COPY apps/cron-rescrape-due-media/crontab /etc/cron.d/cron-rescrape-due-media
COPY apps/cron-rescraping-changes/bin/ /opt/mediacloud/bin/
COPY apps/cron-rescraping-changes/crontab /etc/cron.d/cron-rescraping-changes
COPY apps/cron-set-media-primary-language/src/ /opt/mediacloud/src/cron-set-media-primary-language/
COPY apps/cron-set-media-primary-language/bin/ /opt/mediacloud/bin/
COPY apps/cron-set-media-primary-language/crontab /etc/cron.d/cron-set-media-primary-language
COPY apps/cron-set-media-subject-country/src/ /opt/mediacloud/src/cron-set-media-subject-country/
COPY apps/cron-set-media-subject-country/bin/ /opt/mediacloud/bin/
COPY apps/cron-set-media-subject-country/crontab /etc/cron.d/cron-set-media-subject-country
ENV PYTHONPATH="/opt/mediacloud/src/cron-set-media-primary-language/python:/opt/mediacloud/src/cron-set-media-subject-country/python:/opt/mediacloud/src/cron-generate-media-health/python:/opt/mediacloud/src/cron-generate-daily-rss-dumps/python:${PYTHONPATH}" \
    PERL5LIB="/opt/mediacloud/src/cron-set-media-primary-language/perl:/opt/mediacloud/src/cron-set-media-subject-country/perl:/opt/mediacloud/src/cron-generate-media-health/perl:/opt/mediacloud/src/cron-generate-daily-rss-dumps/perl:${PERL5LIB}"
COPY docker/maintenance-entrypoint.sh /civicsignal-maintenance-entrypoint.sh
COPY docker/cron-job.sh /civicsignal-cron-job.sh
RUN sed -i 's@/var/lib/daily_rss_dumps/@/state/rss/@g' /etc/cron.d/* && chmod 0644 /etc/cron.d/* && sed -i '/^[^#].*root[[:space:]]/s@root[[:space:]]*@root /civicsignal-cron-job.sh @' /etc/cron.d/*
ENTRYPOINT ["/civicsignal-maintenance-entrypoint.sh"]
CMD ["cron", "-f"]

FROM codeforafrica/cs-topics-mine:release@sha256:b78a53fb3cc32ccfc00ff0f14a92e50c4b69713f5a8270c20ac0445e51ee3279 AS topics-mine
USER root
COPY apps/common/src/ /opt/mediacloud/src/common/
COPY apps/extract-and-vector/src/ /opt/mediacloud/src/extract-and-vector/
COPY apps/topics-base/src/ /opt/mediacloud/src/topics-base/
COPY apps/topics-mine/src/ /opt/mediacloud/src/topics-mine/
COPY apps/topics-mine/bin/ /opt/mediacloud/bin/
COPY apps/base/bin/container_memory_limit.sh apps/base/bin/container_cpu_limit.sh /
USER mediacloud

FROM codeforafrica/cs-topics-snapshot:release@sha256:05c538586d778deefe52ec1d80ea4836d675d0838b6944e51b93f0265ced6aaf AS topics-snapshot
USER root
COPY apps/common/src/ /opt/mediacloud/src/common/
COPY apps/extract-and-vector/src/ /opt/mediacloud/src/extract-and-vector/
COPY apps/topics-base/src/ /opt/mediacloud/src/topics-base/
COPY apps/topics-snapshot/src/ /opt/mediacloud/src/topics-snapshot/
COPY apps/topics-snapshot/bin/ /opt/mediacloud/bin/
COPY apps/base/bin/container_memory_limit.sh apps/base/bin/container_cpu_limit.sh /
USER mediacloud

FROM codeforafrica/cs-topics-extract-story-links:release@sha256:6675b41e86687e5673b6d5d70dfcb0df30baf1c871791792a7b53de3bf4f8300 AS topics-extract-story-links
USER root
COPY apps/common/src/ /opt/mediacloud/src/common/
COPY apps/extract-and-vector/src/ /opt/mediacloud/src/extract-and-vector/
COPY apps/topics-base/src/ /opt/mediacloud/src/topics-base/
COPY apps/topics-extract-story-links/src/ /opt/mediacloud/src/topics-extract-story-links/
COPY apps/topics-extract-story-links/bin/ /opt/mediacloud/bin/
COPY apps/base/bin/container_memory_limit.sh apps/base/bin/container_cpu_limit.sh /
USER mediacloud

FROM codeforafrica/cs-topics-fetch-link:release@sha256:63c792cbab51ee34fa227f76186dd24886c5c81ee0870d4a2a2055ecc3753b30 AS topics-fetch-link
USER root
COPY apps/common/src/ /opt/mediacloud/src/common/
COPY apps/extract-and-vector/src/ /opt/mediacloud/src/extract-and-vector/
COPY apps/topics-base/src/ /opt/mediacloud/src/topics-base/
COPY apps/topics-fetch-link/src/ /opt/mediacloud/src/topics-fetch-link/
COPY apps/topics-fetch-link/bin/ /opt/mediacloud/bin/
COPY apps/base/bin/container_memory_limit.sh apps/base/bin/container_cpu_limit.sh /
USER mediacloud

FROM topics-mine AS topics-mine-public
COPY apps/topics-mine-public/bin/ /opt/mediacloud/bin/
CMD ["topics_mine_public_worker.pl"]

FROM webapp-api AS topics-map
USER root
COPY --from=solr-shard-01 /usr/lib/jvm/ /usr/lib/jvm/
ENV PATH="/usr/lib/jvm/java-16-amazon-corretto/bin:${PATH}"
COPY apps/topics-map/src/requirements.txt /var/tmp/topics-map-requirements.txt
RUN pip3 install -r /var/tmp/topics-map-requirements.txt && rm /var/tmp/topics-map-requirements.txt
RUN mkdir -p /opt/fa2l && /dl_to_stdout.sh https://github.com/klarman-cell-observatory/forceatlas2/releases/download/1.0.3/forceatlas2.jar > /opt/fa2l/forceatlas2.jar && /dl_to_stdout.sh https://github.com/klarman-cell-observatory/forceatlas2/releases/download/1.0.3/gephi-toolkit-0.9.2-all.jar > /opt/fa2l/gephi-toolkit.jar
COPY apps/topics-map/src/ /opt/mediacloud/src/topics-map/
COPY apps/topics-map/bin/ /opt/mediacloud/bin/
ENV PYTHONPATH="/opt/mediacloud/src/topics-map/python:${PYTHONPATH}"
USER mediacloud
CMD ["topics_map_worker_wrapper.sh"]


# Group related workers to fit within ECS's ten-container task limit.
# Process budgets leave room for supervisor and runtime overhead.
FROM import-solr-data AS pipeline
USER root
COPY --from=rescrape-media /usr/local/lib/x86_64-linux-gnu/perl/ /usr/local/lib/x86_64-linux-gnu/perl/
COPY --from=rescrape-media /usr/local/share/perl/ /usr/local/share/perl/
COPY --from=crawler-provider /opt/mediacloud/src/crawler-provider/ /opt/mediacloud/src/crawler-provider/
COPY --from=crawler-provider /opt/mediacloud/bin/ /opt/mediacloud/bin/
COPY --from=crawler-fetcher /opt/mediacloud/src/crawler-fetcher/ /opt/mediacloud/src/crawler-fetcher/
COPY --from=crawler-fetcher /opt/mediacloud/bin/ /opt/mediacloud/bin/
COPY --from=extract-and-vector /opt/mediacloud/src/extract-and-vector/ /opt/mediacloud/src/extract-and-vector/
COPY --from=extract-and-vector /opt/mediacloud/bin/ /opt/mediacloud/bin/
COPY --from=rescrape-media /opt/mediacloud/src/rescrape-media/ /opt/mediacloud/src/rescrape-media/
COPY --from=rescrape-media /opt/mediacloud/bin/ /opt/mediacloud/bin/
ENV PYTHONPATH="/opt/mediacloud/src/crawler-provider/python:/opt/mediacloud/src/crawler-fetcher/python:/opt/mediacloud/src/extract-and-vector/python:/opt/mediacloud/src/rescrape-media/python:${PYTHONPATH}"
ENV PERL5LIB="/opt/mediacloud/src/crawler-provider/perl:/opt/mediacloud/src/crawler-fetcher/perl:/opt/mediacloud/src/extract-and-vector/perl:/opt/mediacloud/src/rescrape-media/perl:${PERL5LIB}"
COPY docker/worker-supervisor.py /civicsignal-worker-supervisor.py
COPY docker/pipeline.json /civicsignal-workers.json
COPY apps/cliff-fetch-annotation-and-tag/src/ /opt/mediacloud/src/cliff-fetch-annotation-and-tag/
COPY apps/cliff-fetch-annotation-and-tag/bin/ /opt/mediacloud/bin/
COPY apps/nytlabels-fetch-annotation-and-tag/src/ /opt/mediacloud/src/nytlabels-fetch-annotation-and-tag/
COPY apps/nytlabels-fetch-annotation-and-tag/bin/ /opt/mediacloud/bin/
ENV PYTHONPATH="/opt/mediacloud/src/cliff-fetch-annotation-and-tag/python:/opt/mediacloud/src/nytlabels-fetch-annotation-and-tag/python:${PYTHONPATH}"
USER mediacloud
ENTRYPOINT ["python3", "/civicsignal-worker-supervisor.py"]
CMD ["/civicsignal-workers.json"]

FROM topics-snapshot AS topics
USER root
COPY --from=topics-mine /usr/local/lib/x86_64-linux-gnu/perl/ /usr/local/lib/x86_64-linux-gnu/perl/
COPY --from=topics-mine /usr/local/share/perl/ /usr/local/share/perl/
COPY --from=topics-map /usr/lib/jvm/ /usr/lib/jvm/
COPY --from=topics-map /opt/fa2l/ /opt/fa2l/
COPY apps/topics-map/src/requirements.txt /var/tmp/topics-map-requirements.txt
RUN pip3 install -r /var/tmp/topics-map-requirements.txt && rm /var/tmp/topics-map-requirements.txt
ENV PATH="/usr/lib/jvm/java-16-amazon-corretto/bin:${PATH}"
COPY --from=topics-mine /opt/mediacloud/src/topics-mine/ /opt/mediacloud/src/topics-mine/
COPY apps/topics-mine/bin/ /opt/mediacloud/bin/
COPY apps/topics-mine-public/bin/ /opt/mediacloud/bin/
COPY --from=topics-extract-story-links /opt/mediacloud/src/topics-extract-story-links/ /opt/mediacloud/src/topics-extract-story-links/
COPY apps/topics-extract-story-links/bin/ /opt/mediacloud/bin/
COPY --from=topics-fetch-link /opt/mediacloud/src/topics-fetch-link/ /opt/mediacloud/src/topics-fetch-link/
COPY apps/topics-fetch-link/bin/ /opt/mediacloud/bin/
COPY --from=topics-map /opt/mediacloud/src/topics-map/ /opt/mediacloud/src/topics-map/
COPY apps/topics-map/bin/ /opt/mediacloud/bin/
ENV PYTHONPATH="/opt/mediacloud/src/topics-mine/python:/opt/mediacloud/src/topics-extract-story-links/python:/opt/mediacloud/src/topics-fetch-link/python:/opt/mediacloud/src/topics-map/python:${PYTHONPATH}"
ENV PERL5LIB="/opt/mediacloud/src/topics-mine/perl:/opt/mediacloud/src/topics-extract-story-links/perl:/opt/mediacloud/src/topics-fetch-link/perl:/opt/mediacloud/src/topics-map/perl:${PERL5LIB}"
COPY docker/worker-supervisor.py /civicsignal-worker-supervisor.py
COPY docker/topics.json /civicsignal-workers.json
USER mediacloud
ENTRYPOINT ["python3", "/civicsignal-worker-supervisor.py"]
CMD ["/civicsignal-workers.json"]

# Preserve the deployed geocoder/model artifacts while shipping the current HTTP server.
FROM codeforafrica/cs-cliff-annotator:release@sha256:bb323af74c928a0ec1e1d76fbedc2062f68ea02b7e0136f269e5b1eba15af6b3 AS cliff-artifacts
FROM codeforafrica/cs-nytlabels-annotator:release@sha256:e3f771c919a9015c5fa772b41d34253c81b765bdbe501c4a44d1ac5c8395e48b AS annotators
USER root
COPY --from=cliff-artifacts /usr/lib/jvm/ /usr/lib/jvm/
COPY --from=cliff-artifacts --chown=nobody:nogroup /usr/lib/tomcat7/ /usr/lib/tomcat7/
COPY --from=cliff-artifacts --chown=nobody:nogroup /etc/cliff2/ /etc/cliff2/
COPY apps/nytlabels-annotator/src/crappy-predict-news-labels/ /usr/src/crappy-predict-news-labels/
COPY apps/base/bin/container_memory_limit.sh apps/base/bin/container_cpu_limit.sh /
RUN sed -i 's/port="8080"/port="8082"/g' /usr/lib/tomcat7/conf/server.xml
RUN java_binary=$(find /usr/lib/jvm -type f -path '*/bin/java' | head -1) && test -n "$java_binary" && ln -s "$(dirname "$(dirname "$java_binary")")" /opt/civicsignal-java
ENV JAVA_HOME=/opt/civicsignal-java PATH="/usr/lib/tomcat7/bin:${PATH}" JAVA_OPTS="-Xmx2048m"
COPY docker/worker-supervisor.py /civicsignal-worker-supervisor.py
COPY docker/annotators.json /civicsignal-workers.json
USER nobody
ENTRYPOINT ["python3", "/civicsignal-worker-supervisor.py"]
CMD ["/civicsignal-workers.json"]

FROM ${CIVICSIGNAL_COMPONENT} AS runtime
