#!/bin/bash

# VPS System Information Script
# Collects information about services, resources, and network configuration

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Function to print section headers
print_header() {
    echo -e "\n${BOLD}${CYAN}================================${NC}"
    echo -e "${BOLD}${CYAN}$1${NC}"
    echo -e "${BOLD}${CYAN}================================${NC}"
}

# Function to print sub-headers
print_subheader() {
    echo -e "\n${BOLD}${YELLOW}--- $1 ---${NC}"
}

# Start of report
echo -e "${BOLD}${MAGENTA}╔════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${MAGENTA}║     VPS SYSTEM INFORMATION REPORT      ║${NC}"
echo -e "${BOLD}${MAGENTA}╔════════════════════════════════════════╗${NC}"
echo -e "${BOLD}Generated: $(date)${NC}"

# ============================================
# BASIC SYSTEM INFO
# ============================================
print_header "SYSTEM INFORMATION"

echo -e "${GREEN}Hostname:${NC} $(hostname)"
echo -e "${GREEN}FQDN:${NC} $(hostname -f 2>/dev/null || echo 'Not set')"
echo -e "${GREEN}OS:${NC} $(cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2)"
echo -e "${GREEN}Kernel:${NC} $(uname -r)"
echo -e "${GREEN}Uptime:${NC} $(uptime -p)"

# ============================================
# NETWORK INFORMATION
# ============================================
print_header "NETWORK INFORMATION"

print_subheader "IP Addresses"
echo -e "${GREEN}Public IP:${NC} $(curl -s ifconfig.me || echo 'Unable to fetch')"
echo ""
echo -e "${GREEN}Local IP Addresses:${NC}"
ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}/\d+' | while read ip; do
    interface=$(ip -4 addr show | grep -B 2 "$ip" | head -1 | awk '{print $2}' | sed 's/://')
    echo "  $interface: $ip"
done

# IPv6 if available
if ip -6 addr show | grep -q "inet6.*scope global"; then
    echo ""
    echo -e "${GREEN}IPv6 Addresses:${NC}"
    ip -6 addr show | grep "inet6.*scope global" | awk '{print "  " $2}'
fi

# ============================================
# TAILSCALE STATUS
# ============================================
print_header "TAILSCALE STATUS"

if command -v tailscale &> /dev/null; then
    if systemctl is-active --quiet tailscaled 2>/dev/null || pgrep -x tailscaled > /dev/null; then
        echo -e "${GREEN}Status:${NC} Installed and Running"
        echo ""
        tailscale status 2>/dev/null || echo "Unable to get detailed status"
        echo ""
        echo -e "${GREEN}Tailscale IP:${NC} $(tailscale ip -4 2>/dev/null || echo 'Not connected')"
    else
        echo -e "${YELLOW}Status:${NC} Installed but not running"
    fi
else
    echo -e "${RED}Status:${NC} Not installed"
fi

# ============================================
# RESOURCE USAGE
# ============================================
print_header "RESOURCE USAGE"

print_subheader "CPU Information"
echo -e "${GREEN}CPU Model:${NC} $(lscpu | grep "Model name" | cut -d':' -f2 | xargs)"
echo -e "${GREEN}CPU Cores:${NC} $(nproc) cores"
echo -e "${GREEN}CPU Usage:${NC}"
top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print "  " 100 - $1 "% used"}'

print_subheader "Memory Usage"
free -h | awk 'NR==1{print "  " $0} NR==2{printf "  %-10s %6s %6s %6s %6s\n", $1, $2, $3, $4, $7}'
echo ""
echo -e "${GREEN}Memory Usage Percentage:${NC} $(free | grep Mem | awk '{printf("  %.1f%%\n", $3/$2 * 100.0)}')"

print_subheader "Disk Usage"
df -h | awk 'NR==1{print "  " $0} /^\/dev/{printf "  %-20s %6s %6s %6s %5s %s\n", $1, $2, $3, $4, $5, $6}'

print_subheader "Load Average"
echo -e "${GREEN}Load (1m, 5m, 15m):${NC} $(uptime | awk -F'load average:' '{print $2}')"

# ============================================
# DOCKER SERVICES
# ============================================
print_header "DOCKER SERVICES"

if command -v docker &> /dev/null; then
    if systemctl is-active --quiet docker 2>/dev/null || pgrep -x dockerd > /dev/null; then
        echo -e "${GREEN}Docker Status:${NC} Running"
        echo -e "${GREEN}Docker Version:${NC} $(docker --version 2>/dev/null | cut -d' ' -f3 | tr -d ',')"
        echo ""

        # Running containers
        container_count=$(docker ps -q | wc -l)
        if [ "$container_count" -gt 0 ]; then
            print_subheader "Running Containers ($container_count)"
            docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}" | sed 's/^/  /'

            # Docker Compose projects if docker-compose or docker compose is available
            echo ""
            print_subheader "Container Resource Usage"
            docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}" | sed 's/^/  /'
        else
            echo -e "${YELLOW}No running containers${NC}"
        fi

        # Stopped containers
        stopped_count=$(docker ps -a -q | wc -l)
        running_count=$(docker ps -q | wc -l)
        stopped_only=$((stopped_count - running_count))
        if [ "$stopped_only" -gt 0 ]; then
            echo ""
            print_subheader "Stopped Containers ($stopped_only)"
            docker ps -a --filter "status=exited" --format "table {{.Names}}\t{{.Image}}\t{{.Status}}" | sed 's/^/  /'
        fi

    else
        echo -e "${YELLOW}Docker Status:${NC} Installed but not running"
    fi
else
    echo -e "${RED}Docker:${NC} Not installed"
fi

# ============================================
# NGINX CONFIGURATION
# ============================================
print_header "NGINX CONFIGURATION"

if command -v nginx &> /dev/null; then
    echo -e "${GREEN}Nginx Status:${NC} $(systemctl is-active nginx 2>/dev/null || echo 'Not running')"
    echo -e "${GREEN}Nginx Version:${NC} $(nginx -v 2>&1 | cut -d'/' -f2)"
    echo ""

    # Get server IPs for DNS checking
    SERVER_PUBLIC_IP=$(curl -s --max-time 3 ifconfig.me 2>/dev/null)
    SERVER_IPS=$(hostname -I 2>/dev/null | tr ' ' '\n')

    # Enabled sites
    if [ -d "/etc/nginx/sites-enabled" ]; then
        print_subheader "Enabled Sites (with DNS Check)"
        if [ "$(ls -A /etc/nginx/sites-enabled 2>/dev/null)" ]; then
            for site in /etc/nginx/sites-enabled/*; do
                site_name=$(basename "$site")
                if [ -f "$site" ] || [ -L "$site" ]; then
                    # Try to extract server_name from config
                    server_names=$(grep -h "server_name" "$site" 2>/dev/null | sed 's/.*server_name \(.*\);/\1/' | sed 's/;.*//' | head -1)
                    # Try to extract listen port
                    listen_port=$(grep -h "listen" "$site" 2>/dev/null | grep -v "#" | head -1 | awk '{print $2}' | tr -d ';')
                    echo -e "  ${BLUE}$site_name${NC}"
                    [ -n "$server_names" ] && echo "    Server names: $server_names"
                    [ -n "$listen_port" ] && echo "    Listen: $listen_port"

                    # DNS Resolution check for each server name
                    if [ -n "$server_names" ]; then
                        for domain in $server_names; do
                            # Skip special values
                            if [ "$domain" = "_" ] || [ "$domain" = "localhost" ] || [[ "$domain" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                                continue
                            fi

                            # Resolve domain (try multiple methods)
                            if command -v host &> /dev/null; then
                                resolved_ip=$(host "$domain" 2>/dev/null | grep "has address" | head -1 | awk '{print $NF}')
                            elif command -v dig &> /dev/null; then
                                resolved_ip=$(dig +short "$domain" A 2>/dev/null | grep -v '\.$' | head -1)
                            elif command -v nslookup &> /dev/null; then
                                resolved_ip=$(nslookup "$domain" 2>/dev/null | awk '/^Address: / { print $2 }' | tail -1)
                            else
                                resolved_ip=""
                            fi

                            if [ -z "$resolved_ip" ]; then
                                echo -e "      ${YELLOW}⚠${NC}  $domain → ${RED}No DNS record${NC}"
                            elif [ "$resolved_ip" = "$SERVER_PUBLIC_IP" ]; then
                                echo -e "      ${GREEN}✓${NC}  $domain → $resolved_ip ${GREEN}(points here)${NC}"
                            else
                                # Check if it points to any local IP
                                if echo "$SERVER_IPS" | grep -q "^$resolved_ip$"; then
                                    echo -e "      ${GREEN}✓${NC}  $domain → $resolved_ip ${GREEN}(local IP)${NC}"
                                else
                                    echo -e "      ${YELLOW}⚠${NC}  $domain → $resolved_ip ${YELLOW}(different server)${NC}"
                                fi
                            fi
                        done
                    fi
                fi
            done
        else
            echo -e "  ${YELLOW}No enabled sites${NC}"
        fi
    fi

    # Available sites
    if [ -d "/etc/nginx/sites-available" ]; then
        print_subheader "Available Sites"
        if [ "$(ls -A /etc/nginx/sites-available 2>/dev/null)" ]; then
            ls -1 /etc/nginx/sites-available/ | while read site; do
                if [ -L "/etc/nginx/sites-enabled/$site" ]; then
                    echo -e "  $site ${GREEN}(enabled)${NC}"
                else
                    echo -e "  $site ${YELLOW}(disabled)${NC}"
                fi
            done
        else
            echo -e "  ${YELLOW}No available sites${NC}"
        fi
    fi

    # Check nginx config validity
    echo ""
    print_subheader "Configuration Test"
    if nginx -t 2>&1 | grep -q "successful"; then
        echo -e "  ${GREEN}Configuration is valid${NC}"
    else
        echo -e "  ${RED}Configuration has errors${NC}"
        nginx -t 2>&1 | sed 's/^/  /'
    fi
else
    echo -e "${RED}Nginx:${NC} Not installed"
fi

# ============================================
# ACTIVE SERVICES
# ============================================
print_header "KEY SYSTEM SERVICES"

services=("ssh" "nginx" "docker" "tailscaled" "fail2ban" "ufw" "mysql" "mariadb" "postgresql" "redis")
echo -e "${GREEN}Service Status:${NC}"
for service in "${services[@]}"; do
    if systemctl list-unit-files | grep -q "^${service}.service"; then
        status=$(systemctl is-active "$service" 2>/dev/null)
        if [ "$status" = "active" ]; then
            echo -e "  ${GREEN}●${NC} $service: ${GREEN}running${NC}"
        else
            echo -e "  ${RED}○${NC} $service: ${YELLOW}stopped${NC}"
        fi
    fi
done

# ============================================
# LISTENING PORTS
# ============================================
print_header "LISTENING PORTS"

echo -e "${GREEN}TCP/UDP Ports:${NC}"
if command -v ss &> /dev/null; then
    ss -tulpn 2>/dev/null | grep LISTEN | while read -r line; do
        port=$(echo "$line" | awk '{split($5, a, ":"); print a[length(a)]}')
        proto=$(echo "$line" | awk '{print toupper(substr($1, 1, 3))}')
        process=$(echo "$line" | grep -oP '"\K[^"]+' | head -1)
        [ -z "$process" ] && process="-"
        echo "$port|$proto|$process"
    done | sort -t'|' -n -k1 | uniq | awk -F'|' '{printf "  %-8s %-6s %s\n", $1, $2, $3}'
elif command -v netstat &> /dev/null; then
    netstat -tulpn 2>/dev/null | grep LISTEN | while read -r line; do
        port=$(echo "$line" | awk '{split($4, a, ":"); print a[length(a)]}')
        proto=$(echo "$line" | awk '{p = toupper($1); gsub(/[0-9]+/, "", p); print p}')
        process=$(echo "$line" | awk '{if ($7 != "-") {split($7, p, "/"); print p[2]} else {print "-"}}')
        echo "$port|$proto|$process"
    done | sort -t'|' -n -k1 | uniq | awk -F'|' '{printf "  %-8s %-6s %s\n", $1, $2, $3}'
else
    echo -e "  ${YELLOW}ss/netstat not available${NC}"
fi

# ============================================
# END OF REPORT
# ============================================
echo ""
echo -e "${BOLD}${MAGENTA}╚════════════════════════════════════════╝${NC}"
echo -e "${BOLD}${MAGENTA}║          END OF REPORT                 ║${NC}"
echo -e "${BOLD}${MAGENTA}╚════════════════════════════════════════╝${NC}"
echo ""
