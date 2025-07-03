FROM httpd:2.4-alpine

# Copy custom index.html to Apache document root
COPY index.html /usr/local/apache2/htdocs/

# Expose port 80
EXPOSE 80

# Add health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget --quiet --tries=1 --spider http://localhost/ || exit 1

# Run Apache in foreground
CMD ["httpd-foreground"]
