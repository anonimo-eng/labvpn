#!/usr/bin/bash

set -euo pipefail 

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

trap ctrl_c INT

function ctrl_c(){
		echo ""
		echo -e "${RED}[!]${NC} Interrupción detectada"
		if pgrep -x "openvpn" &>/dev/null; then
				echo -e "${BLUE}[*]${NC} Deteniendo VPN activa..."
				sudo pkill openvpn 2>/dev/null
				echo -e "${GREEN}[+]${NC} VPN detenida"
		fi
		exit 1
}

function check_requirements(){
	# Verificar openvpn
    if ! command -v openvpn &>/dev/null; then
        echo -e "${RED}[!]${NC} openvpn no está instalado"
        echo -e "${BLUE}[*]${NC} Instálalo con: sudo pacman -S openvpn o sudo apt-get openvpn"
        exit 1
    fi
    echo -e "${GREEN}[+]${NC} openvpn encontrado"

	# Verificar curl
	if ! command -v curl &>/dev/null; then
			echo -e "${RED}[!]${NC} curl no está instalado"
			echo -e "${BLUE}[*]${NC} Instálalo con: sudo pacman -S curl o sudo apt-get curl"
			exit 1
	fi
	echo -e "${GREEN}[+]${NC} curl encontrado"

	# Verificar internet
	if ! curl -s --max-time 3 https://api64.ipify.org &>/dev/null; then
			echo -e "${RED}[!]${NC} Sin conexión a internet"
			exit 1
	fi
	echo -e "${GREEN}[+]${NC} Conexión a internet OK"
}

function spinner(){
    local pid=$1
    local mensaje="${2:-Esperando...}"
    local frames=('|' '/' '-' '\')
    local i=0

    while kill -0 "$pid" 2>/dev/null; do
        printf "\r${BLUE}[*]${NC} %s %s" "$mensaje" "${frames[$i]}"
        i=$(( (i + 1) % ${#frames[@]} ))
        sleep 0.1
    done
    printf "\r%-50s\r" " "  # limpia la línea
}

function identify_ovpn_files(){
		echo -e "${BLUE}[*]${NC} Buscando archivos .ovpn..."
		
		ovpn_find=$(find /home /root /etc -name "*.ovpn" -type f 2>/dev/null) || true
		
		if [[ -z "$ovpn_find" ]]; then 
				echo -e "${RED}[!]${NC} Sin VPN(s) disponible..."
				exit 1
		else
				echo -e "${BLUE}[*]${NC} VPN(s) encontrada(s)"
		fi
}

function wait_for_tun0(){
    local vpn_pid="$1"
    local intentos=0
    local frames=('|' '/' '-' '\')
    local i=0

    while ! ip link show tun0 &>/dev/null; do
        printf "\r${BLUE}[*]${NC} Esperando conexión... %s" "${frames[$i]}"
        i=$(( (i + 1) % ${#frames[@]} ))
        sleep 0.1
        intentos=$((intentos + 1))

        if [[ $intentos -ge 300 ]]; then  # 30 segundos (300 * 0.1)
            printf "\r%-50s\r" " "
            echo -e "${RED}[!]${NC} Timeout: no se pudo conectar"
            sudo kill "$vpn_pid" 2>/dev/null
            exit 1
        fi
    done

    printf "\r%-50s\r" " "  # limpia la línea del spinner
}

function check_active_vpn(){
    if pgrep -x "openvpn" &>/dev/null; then
        echo -e "${BLUE}[!]${NC} Ya hay una VPN activa"
        read -rp "¿Deseas desconectarla primero? (s/n): " respuesta
        if [[ "$respuesta" == "s" ]]; then
            sudo pkill openvpn
            echo -e "${GREEN}[+]${NC} VPN desconectada"
            sleep 1
        else
            echo -e "${RED}[-]${NC} Saliendo..."
            exit 0
        fi
    fi
}

function identify_plataform(){
		local file="$1"
		local content

		content=$(cat "$file" 2>/dev/null)

		if echo "$content" | grep -qiE 'hackthebox\.eu|htb-|\.htb'; then
				echo "HackTheBox"
    	elif echo "$content" | grep -qiE 'tryhackme\.com|thm-|\.thm'; then
        		echo "TryHackMe"
    	elif echo "$content" | grep -qiE 'offensive-security\.com|oscp|oswp|offsec'; then
        		echo "OffSec / PWK"
    	elif echo "$content" | grep -qiE 'pentesterlab\.com'; then
        		echo "PentesterLab"
   		 elif echo "$content" | grep -qiE 'hacking\.land|hl-'; then
        		echo "Hacking.Land"
    	elif echo "$content" | grep -qiE 'vulnhub'; then
        		echo "VulnHub"
		
		# Busca en la ruta del archivo
		elif echo "$file" | grep -qiE 'hackthebox|htb'; then
				echo "HackTheBox"
		elif echo "$file" | grep -qiE 'tryhackme|thm'; then
				echo "TryHackme"
		elif echo "$file" | grep -qiE 'offensive-security|oscp|offsec'; then
				echo "OffSec / PWK"
		else
        		echo "Desconocido"
        fi
}

function get_ip(){
    curl -s -4 https://api.ipify.org
}

function get_vpn_ip(){
		ip -4 addr show tun0 | grep -oP '(?<=inet\s)\d+(\.\d+){3}'

}

function connect_vpn(){
    clear
    local vpn_file="$1"
    local port
    port=$(grep -m1 '^remote ' "$vpn_file" | awk '{print $3}')

    sudo -v

    echo -e "${BLUE}[*]${NC} Conectando a: $(basename "$vpn_file")"

    sudo openvpn --config "$vpn_file" > /dev/null 2>&2 < /dev/null &
    local vpn_pid=$!

	wait_for_tun0 "$vpn_pid"

    echo -e "${GREEN}[+]${NC} Conectado"
	echo -e "${GREEN}[+]${NC} IP Pública: $(get_ip)"
	echo -e "${GREEN}[+]${NC} IP VPN:     $(get_vpn_ip)"
    echo -e "${GREEN}[+]${NC} Puerto: $port"
    echo -e "${GREEN}[+]${NC} PID:    $vpn_pid"
	
	vpn_menu "$vpn_pid"
}

function select_vpn(){
	echo ""
	echo -e  "${BLUE}[*]${NC} Selecciona la plataforma:"
	echo " 1) HackTheBox"
	echo " 2) TryHackme"
	echo " 3) OffSec / PWK"
	echo " 0) Salir"
	echo ""
	read -rp "Opción: " opcion

	case "$opcion" in
			1) plataforma_filtro="HackTheBox" ;;
			2) plataforma_filtro="TryHackme" ;;
			3) plataforma_filtro="OffSec / PWK" ;;
			0) echo -e "${RED}[-]${NC} Saliendo..."; exit 0 ;;
			*) echo -e "${RED}[!]${NC} Opción inválida"; exit 1 ;;
	esac

	echo ""
	echo -e "${BLUE}[*]${NC} VPNs disponibles para $plataforma_filtro"

	local i=1
	local vpn_list=()
	while IFS= read -r file; do
			plataforma=$(identify_plataform "$file")
			if [[ "$plataforma" == "$plataforma_filtro" ]]; then
					echo " $i) $(basename "$file")"
					vpn_list+=("$file")
					i=$((i + 1))
			fi
	done < <(find /home /root /etc -name "*.ovpn" -type f 2>/dev/null)

	if [[ ${#vpn_list[@]} -eq 0 ]]; then
			echo -e "${RED}[!]${NC} No hay VPNs para $plataforma_filtro"
			exit 1
	fi

	echo ""
	read -rp "Elige VPN (número): " vpn_opcion
	vpn_elegida="${vpn_list[$((vpn_opcion - 1))]}"

	connect_vpn "$vpn_elegida"
}

function vpn_menu(){
    local vpn_pid="$1"
    echo ""
    echo -e "${BLUE}[*]${NC} ¿Qué deseas hacer?"
    echo "  1) Cambiar de VPN"
    echo "  2) Desconectar VPN"
    echo "  0) Salir (VPN sigue activa)"
    echo ""
    read -rp "Opción: " opcion

    case "$opcion" in
        1)
            sudo kill "$vpn_pid" 2>/dev/null
            sleep 1
            select_vpn
            ;;
        2)
            sudo kill "$vpn_pid" 2>/dev/null
            echo -e "${GREEN}[+]${NC} VPN desconectada"
            exit 0
            ;;
        0)
            echo -e "${BLUE}[*]${NC} VPN activa con PID: $vpn_pid"
            exit 0
            ;;
        *)
            echo -e "${RED}[!]${NC} Opción inválida"
            vpn_menu "$vpn_pid"
            ;;
    esac
}

function main(){
		check_requirements
		check_active_vpn
		identify_ovpn_files
		select_vpn
}
#		echo ""
#		echo "[*] Identificando plataformas"
#
#		while IFS= read -r file; do
#				plataforma=$(identify_plataform "$file")
#				printf " %-50s -> %s\n" "$(basename "$file")" "$plataforma"
#		done < <(find / -name "*.ovpn" -type f -not -path "/timeshift/*" 2>/dev/null)
#}

main
