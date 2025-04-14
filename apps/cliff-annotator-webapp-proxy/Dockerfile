#
# Proxy to CLIFF annotator, roundrobins between cliff-annotator instances
#

FROM codeforafrica/cs-nginx-base

# Copy configuration
COPY nginx/include/cliff-annotator-webapp-proxy.conf /etc/nginx/include/

# Web server's port
EXPOSE 80

# Run Nginx
CMD ["nginx"]
