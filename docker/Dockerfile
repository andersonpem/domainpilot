# Use the official Caddy image as the base image
FROM caddy:2

# Install Docker CLI, jq, and figlet
RUN apk add --no-cache docker-cli jq figlet bash nss nss-tools

# Add your custom script to the container
ADD docker/caddy-json-config.sh /usr/local/bin/domainpilot
RUN chmod +x /usr/local/bin/domainpilot

# Optional: Copy any additional files your script depends on
COPY docker/includes.sh /opt/includes.sh

# Set the script as the container's entrypoint
ENTRYPOINT ["domainpilot"]

# Caddy will run on ports 80 and 443
EXPOSE 80 443