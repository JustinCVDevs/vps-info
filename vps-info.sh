#!/bin/bash

# VPS System Information Script - CSV Output
# Collects information about services, resources, and network configuration
# Output format: CSV for easy import into Excel
# Usage: ./vps-info.sh > server.csv
# Combine multiple servers: cat server1.csv server2.csv server3.csv > all-servers.csv

# Get basic info
HOSTNAME=$(hostname)
FQDN=$(hostname -f 2>/dev/null || echo 'Not set')
OS=$(cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d'"' -f2 || echo 'Unknown')
KERNEL=$(uname -r)
UPTIME=$(uptime -p 2>/dev/null || uptime | awk '{print $3}')
PUBLIC_IP=$(curl -s --max-time 3 ifconfig.me 2>/dev/null || echo 'Unknown')
CPU_MODEL=$(lscpu 2>/dev/null | grep "Model name" | cut -d':' -f2 | xargs | sed 's/,//g' || echo 'Unknown')
CPU_CORES=$(nproc)
CPU_USAGE=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1}')
MEM_TOTAL=$(free -h | awk '/^Mem:/{print $2}')
MEM_USED=$(free -h | awk '/^Mem:/{print $3}')
MEM_PERCENT=$(free | grep Mem | awk '{printf("%.1f", $3/$2 * 100.0)}')
DISK_TOTAL=$(df -h / | awk 'NR==2{print $2}')
DISK_USED=$(df -h / | awk 'NR==2{print $3}')
DISK_PERCENT=$(df -h / | awk 'NR==2{print $5}')
LOAD_AVG=$(uptime | awk -F'load average:' '{print $2}' | xargs)

# Tailscale status
if command -v tailscale &> /dev/null && (systemctl is-active --quiet tailscaled 2>/dev/null || pgrep -x tailscaled > /dev/null); then
    TAILSCALE_STATUS="Active"
    TAILSCALE_IP=$(tailscale ip -4 2>/dev/null || echo 'N/A')
else
    TAILSCALE_STATUS="Not installed/inactive"
    TAILSCALE_IP="N/A"
fi

# Docker status
if command -v docker &> /dev/null && (systemctl is-active --quiet docker 2>/dev/null || pgrep -x dockerd > /dev/null); then
    DOCKER_STATUS="Running"
    DOCKER_VERSION=$(docker --version 2>/dev/null | cut -d' ' -f3 | tr -d ',' || echo 'Unknown')
    DOCKER_CONTAINERS=$(docker ps -q | wc -l)
    DOCKER_CONTAINERS_STOPPED=$(docker ps -a -q | wc -l)
    DOCKER_CONTAINERS_STOPPED=$((DOCKER_CONTAINERS_STOPPED - DOCKER_CONTAINERS))
else
    DOCKER_STATUS="Not installed/inactive"
    DOCKER_VERSION="N/A"
    DOCKER_CONTAINERS=0
    DOCKER_CONTAINERS_STOPPED=0
fi

# Nginx status
if command -v nginx &> /dev/null; then
    NGINX_STATUS=$(systemctl is-active nginx 2>/dev/null || echo 'Stopped')
    NGINX_VERSION=$(nginx -v 2>&1 | cut -d'/' -f2)
    NGINX_SITES=$(ls -1 /etc/nginx/sites-enabled 2>/dev/null | wc -l)
else
    NGINX_STATUS="Not installed"
    NGINX_VERSION="N/A"
    NGINX_SITES=0
fi

# Key services
SSH_STATUS=$(systemctl is-active ssh 2>/dev/null || systemctl is-active sshd 2>/dev/null || echo 'unknown' | tr -d '\n')
FAIL2BAN_STATUS=$(systemctl is-active fail2ban 2>/dev/null || echo 'inactive' | tr -d '\n')
UFW_STATUS=$(systemctl is-active ufw 2>/dev/null || echo 'inactive' | tr -d '\n')

# ============================================
# CSV OUTPUT - SERVER SUMMARY
# ============================================
echo "=== SERVER_SUMMARY ==="
echo "Hostname,FQDN,Public_IP,Tailscale_IP,OS,Kernel,Uptime,CPU_Model,CPU_Cores,CPU_Usage_%,Memory_Total,Memory_Used,Memory_%,Disk_Total,Disk_Used,Disk_%,Load_Avg,Docker_Status,Docker_Running,Docker_Stopped,Nginx_Status,Nginx_Sites,SSH,Fail2Ban,UFW,Tailscale"
echo "\"$HOSTNAME\",\"$FQDN\",\"$PUBLIC_IP\",\"$TAILSCALE_IP\",\"$OS\",\"$KERNEL\",\"$UPTIME\",\"$CPU_MODEL\",\"$CPU_CORES\",\"$CPU_USAGE\",\"$MEM_TOTAL\",\"$MEM_USED\",\"$MEM_PERCENT\",\"$DISK_TOTAL\",\"$DISK_USED\",\"$DISK_PERCENT\",\"$LOAD_AVG\",\"$DOCKER_STATUS\",\"$DOCKER_CONTAINERS\",\"$DOCKER_CONTAINERS_STOPPED\",\"$NGINX_STATUS\",\"$NGINX_SITES\",\"$SSH_STATUS\",\"$FAIL2BAN_STATUS\",\"$UFW_STATUS\",\"$TAILSCALE_STATUS\""
echo ""

# ============================================
# CSV OUTPUT - DOCKER CONTAINERS
# ============================================
echo "=== DOCKER_CONTAINERS ==="
echo "Hostname,Container_Name,Image,Status,CPU_%,Memory_Usage,Ports"

if command -v docker &> /dev/null && [ "$DOCKER_STATUS" = "Running" ]; then
    # Get all containers
    docker ps -a --format "{{.Names}}@@@{{.Image}}@@@{{.Status}}" 2>/dev/null | while read -r line; do
        name=$(echo "$line" | cut -d'@' -f1)
        image=$(echo "$line" | cut -d'@' -f4)
        status=$(echo "$line" | cut -d'@' -f7-)

        # Get resource stats for running containers
        if [[ "$status" == Up* ]]; then
            stats=$(docker stats --no-stream --format "{{.CPUPerc}}@@@{{.MemUsage}}" "$name" 2>/dev/null || echo "N/A@@@N/A")
            cpu=$(echo "$stats" | cut -d'@' -f1)
            mem=$(echo "$stats" | cut -d'@' -f4 | awk '{print $1}')
            ports=$(docker port "$name" 2>/dev/null | tr '\n' ';' | sed 's/;$//' | sed 's/,//g')
        else
            cpu="N/A"
            mem="N/A"
            ports="N/A"
        fi

        # Clean up values for CSV
        name_clean=$(echo "$name" | sed 's/,/-/g')
        image_clean=$(echo "$image" | sed 's/,/-/g')
        status_clean=$(echo "$status" | sed 's/,/-/g')
        ports_clean=$(echo "$ports" | sed 's/,/-/g')

        echo "\"$HOSTNAME\",\"$name_clean\",\"$image_clean\",\"$status_clean\",\"$cpu\",\"$mem\",\"$ports_clean\""
    done
fi
echo ""

# ============================================
# CSV OUTPUT - NGINX SITES WITH DNS CHECK
# ============================================
echo "=== NGINX_SITES ==="
echo "Hostname,Site_Config,Server_Name,Listen_Port,DNS_Resolves_To,DNS_Status"

if command -v nginx &> /dev/null && [ -d "/etc/nginx/sites-enabled" ]; then
    for site in /etc/nginx/sites-enabled/*; do
        if [ -f "$site" ] || [ -L "$site" ]; then
            site_name=$(basename "$site")
            server_names=$(grep -h "server_name" "$site" 2>/dev/null | sed 's/.*server_name \(.*\);/\1/' | sed 's/;.*//' | head -1 | xargs)
            listen_port=$(grep -h "listen" "$site" 2>/dev/null | grep -v "#" | head -1 | awk '{print $2}' | tr -d ';')

            # Check each server name for DNS
            if [ -n "$server_names" ]; then
                for domain in $server_names; do
                    # Skip special values
                    if [ "$domain" = "_" ] || [ "$domain" = "localhost" ] || [[ "$domain" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                        continue
                    fi

                    # Resolve domain
                    if command -v host &> /dev/null; then
                        resolved_ip=$(host "$domain" 2>/dev/null | grep "has address" | head -1 | awk '{print $NF}')
                    elif command -v dig &> /dev/null; then
                        resolved_ip=$(dig +short "$domain" A 2>/dev/null | grep -v '\.$' | head -1)
                    elif command -v nslookup &> /dev/null; then
                        resolved_ip=$(nslookup "$domain" 2>/dev/null | awk '/^Address: / { print $2 }' | tail -1)
                    else
                        resolved_ip="Unknown"
                    fi

                    # Determine DNS status
                    if [ -z "$resolved_ip" ] || [ "$resolved_ip" = "Unknown" ]; then
                        dns_status="No DNS Record"
                        resolved_ip="N/A"
                    elif [ "$resolved_ip" = "$PUBLIC_IP" ]; then
                        dns_status="Points Here"
                    else
                        dns_status="Different Server"
                    fi

                    # Clean values
                    site_name_clean=$(echo "$site_name" | sed 's/,/-/g')
                    domain_clean=$(echo "$domain" | sed 's/,/-/g')

                    echo "\"$HOSTNAME\",\"$site_name_clean\",\"$domain_clean\",\"$listen_port\",\"$resolved_ip\",\"$dns_status\""
                done
            else
                site_name_clean=$(echo "$site_name" | sed 's/,/-/g')
                echo "\"$HOSTNAME\",\"$site_name_clean\",\"N/A\",\"$listen_port\",\"N/A\",\"No server_name\""
            fi
        fi
    done
fi
echo ""

# ============================================
# CSV OUTPUT - LISTENING PORTS
# ============================================
echo "=== LISTENING_PORTS ==="
echo "Hostname,Port,Protocol,Process"

if command -v ss &> /dev/null; then
    ss -tulpn 2>/dev/null | grep LISTEN | while read -r line; do
        port=$(echo "$line" | awk '{split($5, a, ":"); print a[length(a)]}')
        proto=$(echo "$line" | awk '{print toupper(substr($1, 1, 3))}')
        process=$(echo "$line" | grep -oP '"\K[^"]+' | head -1 | sed 's/,/-/g')
        [ -z "$process" ] && process="Unknown"
        echo "$port|$proto|$process"
    done | sort -t'|' -n -k1 | uniq | while IFS='|' read -r port proto process; do
        echo "\"$HOSTNAME\",\"$port\",\"$proto\",\"$process\""
    done
elif command -v netstat &> /dev/null; then
    netstat -tulpn 2>/dev/null | grep LISTEN | while read -r line; do
        port=$(echo "$line" | awk '{split($4, a, ":"); print a[length(a)]}')
        proto=$(echo "$line" | awk '{p = toupper($1); gsub(/[0-9]+/, "", p); print p}')
        process=$(echo "$line" | awk '{if ($7 != "-") {split($7, p, "/"); print p[2]} else {print "Unknown"}}' | sed 's/,/-/g')
        echo "$port|$proto|$process"
    done | sort -t'|' -n -k1 | uniq | while IFS='|' read -r port proto process; do
        echo "\"$HOSTNAME\",\"$port\",\"$proto\",\"$process\""
    done
fi
echo ""

# ============================================
# CSV OUTPUT - SYSTEM SERVICES
# ============================================
echo "=== SYSTEM_SERVICES ==="
echo "Hostname,Service,Status"

services=("ssh" "sshd" "nginx" "docker" "tailscaled" "fail2ban" "ufw" "mysql" "mariadb" "postgresql" "redis-server" "apache2")
for service in "${services[@]}"; do
    if systemctl list-unit-files 2>/dev/null | grep -q "^${service}.service"; then
        status=$(systemctl is-active "$service" 2>/dev/null || echo "inactive")
        echo "\"$HOSTNAME\",\"$service\",\"$status\""
    fi
done
echo ""
