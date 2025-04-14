#
# Proxy to NYTLabels annotator, roundrobins between nytlabels-annotator instances
#

FROM codeforafrica/cs-nginx-base

# Copy configuration
COPY nginx/include/nytlabels-annotator-webapp-proxy.conf /etc/nginx/include/

# Web server's port
EXPOSE 80

# Run Nginx
CMD ["nginx"]
