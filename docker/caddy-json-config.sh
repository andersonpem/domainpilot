#!/bin/bash
source /opt/includes.sh

cPrint info "Starting up the container..."
# File where the JSON configuration will be stored
CADDY_CONFIG_JSON="/etc/caddy/config.json"

# Check if the Caddy JSON configuration exists, if not create it
if [ ! -f "$CADDY_CONFIG_JSON" ]; then
    cPrint info "Creating initial Caddy JSON configuration."
    # Create an initial JSON configuration with admin API and basic HTTP server settings
    echo '{
            "admin": {
              "listen": "localhost:2019"
            },
            "apps": {
              "http": {
                "servers": {
                  "srv0": {
                    "listen": [":80", ":443"],
                    "routes": []
                  }
                }
              },
              "tls": {
                "automation": {
                  "policies": [
                    {
                      "subjects": ["*.docker.local"],
                      "issuers": [
                        {
                          "module": "internal",
                          "ca": "local",
                          "lifetime": "87600h"
                        }
                      ]
                    }
                  ]
                }
              }
            }
          }
' > $CADDY_CONFIG_JSON
    cPrint info "Caddy JSON configuration created at $CADDY_CONFIG_JSON"
fi

# Function to update Caddy JSON configuration
update_caddy_json_config() {
    local container_name=$1
    local action=$2

    # Extract domain name using 'CADDY_VIRTUAL_HOST' environment variable
    local domain=$(docker inspect --format '{{range $index, $value := .Config.Env}}{{println $value}}{{end}}' $container_name | grep 'DOMAINPILOT_VHOST=' | cut -d '=' -f2)

    if [ -z "$domain" ]; then
        cPrint info "No domain found for container $cL_info$container_name$cl_reset"
        return
    fi

    # Read current configuration
    local current_config=$(cat $CADDY_CONFIG_JSON)

    # Update the JSON configuration based on action
    if [ "$action" == "start" ]; then
        # Add configuration for new domain with self-signed TLS
        cPrint info "Adding the domain $domain to Caddy JSON configuration..."
        local new_config=$(jq '.apps.http.servers.srv0.routes += [{"match": [{"host": ["'$domain'"]}],"handle": [{"handler": "reverse_proxy","upstreams": [{"dial": "'$container_name':80"}]}],"terminal": true}] | .apps.tls.automation.policies += [{"subjects": ["'$domain'"],"issuers": [{"module": "internal", "lifetime": "87600h"}]}]' <<< "$current_config")
    elif [ "$action" == "die" ]; then
        # Remove configuration for the domain
        cPrint info "Removing the domain $domain to Caddy JSON configuration..."
        local new_config=$(jq 'del(.apps.http.servers.srv0.routes[] | select(.match[].host[] == "'$domain'")) | del(.apps.tls.automation.policies[] | select(.subjects[] == "'$domain'"))' <<< "$current_config")
    fi


    # Write the updated configuration
    echo "$new_config" > $CADDY_CONFIG_JSON

    # Check if DEBUG environment variable is set and equals 1
    if [ "${DEBUG}" == "1" ]; then
        echo $new_config
    fi


    # Reload Caddy to apply changes
    cPrint info "Reloading Caddy"
    caddy reload --config $CADDY_CONFIG_JSON
}

caddy start --config $CADDY_CONFIG_JSON


figlet "DomainPilot"
echo -e "${cl_success}Your Trusted Copilot for Secure Web Traffic${cl_reset}"
echo -e "${cl_info}By AndersonPEM <https://github.com/andersonpem>${cl_reset}"
cPrint info "Make sure to add the env var ${cl_info}'CADDY_VIRTUAL_HOST'${cl_reset} to your containers with the domain name you want to use."
cPrint info "Make sure to add the network ${cl_info}'domainpilot-proxy'${cl_reset} for the containers you want to use with DomainPilot."
cPrint status "Listening to Docker container events..."
# Listen for Docker start and die events

docker events --filter 'event=start' --filter 'event=die' --format '{{json .}}' | while read event; do
    container_name=$(echo $event | jq -r '.Actor.Attributes.name')
    event_status=$(echo $event | jq -r '.status')
    if [ "$event_status" == "start" ] || [ "$event_status" == "die" ]; then
        update_caddy_json_config $container_name $event_status
    fi
done
