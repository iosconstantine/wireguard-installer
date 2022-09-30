#!/bin/bash

# https://github.com/iosconstantine/wireguard-installer

RED='\033[0;31m'
ORANGE='\033[0;33m'
NC='\033[0m'

function isRoot() {
	if [ "${EUID}" -ne 0 ]; then
		echo "Вы должны запустить этот скрипт как root"
		exit 1
	fi
}

function checkVirt() {
	if [ "$(systemd-detect-virt)" == "openvz" ]; then
		echo "OpenVZ не поддерживается"
		exit 1
	fi

	if [ "$(systemd-detect-virt)" == "lxc" ]; then
		echo "LXC не поддерживается (пока)."
		echo "WireGuard технически может работать в контейнере LXC,"
		echo "но модуль ядра должен быть установлен на хосте,"
		echo "контейнер должен быть запущен с определенными параметрами"
		echo "и только инструменты должны быть установлены в контейнере."
		exit 1
	fi
}

function checkOS() {
	# Проверка версии OS
	if 
	if [[ -e /etc/debian_version ]]; then
		source /etc/os-release
		OS="${ID}" # debian или ubuntu
		if [[ ${ID} == "debian" || ${ID} == "raspbian" ]]; then
			if [[ ${VERSION_ID} -lt 10 ]]; then
				echo "Ваша версия Debian (${VERSION_ID}) не поддерживается. Пожалуйста используйте Debian 10 Buster или выше"
				exit 1
			fi
			OS=debian # перезаписать если raspbian
		fi
	elif [[ -e /etc/fedora-release ]]; then
		source /etc/os-release
		OS="${ID}"
	elif [[ -e /etc/centos-release ]]; then
		source /etc/os-release
		OS=centos
	elif [[ -e /etc/oracle-release ]]; then
		source /etc/os-release
		OS=oracle
	elif [[ -e /etc/arch-release ]]; then
		OS=arch
	else
		echo "Похоже, вы не используете этот скрипт в системе Debian, Ubuntu, Fedora, CentOS, Oracle или Arch Linux."
		exit 1
	fi
}

function initialCheck() {
	isRoot
	checkVirt
}

function installQuestions() {
	echo "Добро пожаловать в программу установки WireGuard!"
	echo "Репозиторий git доступен по адресу: https://github.com/iosconstantine/wireguard-installer"
	echo ""
	echo "Прежде чем приступить к настройке, я должен задать вам несколько вопросов."
	echo "Вы можете оставить параметры по умолчанию и просто нажать Enter, если они Вас устраивают."
	echo ""

	# Обнаружение публичного IPv4 адреса и предварительное заполнение для пользователя
	SERVER_PUB_IP=$(ip -4 addr | sed -ne 's|^.* inet \([^/]*\)/.* scope global.*$|\1|p' | awk '{print $1}' | head -1)
	read -rp "Публичный адрес IPv4: " -e -i "${SERVER_PUB_IP}" SERVER_PUB_IP

	# Обнаружение публичного интерфейса и предварительное заполнение для пользователя
	SERVER_NIC="$(ip -4 route ls | grep default | grep -Po '(?<=dev )(\S+)' | head -1)"
	until [[ ${SERVER_PUB_NIC} =~ ^[a-zA-Z0-9_]+$ ]]; do
		read -rp "Публичный интерфейс: " -e -i "${SERVER_NIC}" SERVER_PUB_NIC
	done

	until [[ ${SERVER_WG_NIC} =~ ^[a-zA-Z0-9_]+$ && ${#SERVER_WG_NIC} -lt 16 ]]; do
		read -rp "Название интерфейса WireGuard: " -e -i wg0 SERVER_WG_NIC
	done

	until [[ ${SERVER_WG_IPV4} =~ ^([0-9]{1,3}\.){3} ]]; do
		read -rp "IPv4 сервера WireGuard: " -e -i 10.0.0.1 SERVER_WG_IPV4
	done

	# Порт, который будет слушать наш Wireguard сервер
	RANDOM_PORT=$(shuf -i49152-65535 -n1)
	until [[ ${SERVER_PORT} =~ ^[0-9]+$ ]] && [ "${SERVER_PORT}" -ge 1 ] && [ "${SERVER_PORT}" -le 65535 ]; do
		read -rp "Порт сервера WireGuard [1-65535]: " -e -i "51830" SERVER_PORT
	done

	# Adguard DNS по умолчанию
	until [[ ${CLIENT_DNS} =~ ^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$ ]]; do
		read -rp "Первый DNS для использования: " -e -i 8.8.8.8 CLIENT_DNS
	done
	
	echo ""
	echo "Отлично, это было все, что мне было нужно. Теперь мы готовы настроить Ваш сервер WireGuard."
	echo "Вы сможете создать клиента в конце установки."
	read -n1 -r -p "Нажмите любую клавишу для продолжения..."
}

function setupUbuntu() {
	apt-get update
	apt-get upgrade -y
	apt-get install -y wireguard iptables resolvconf qrencode
}}

function installWireGuard() {
	installQuestions
	setupUbuntu

	# Убедитесь, что каталог существует (это не относится к Fedora)
	mkdir /etc/wireguard >/dev/null 2>&1

	chmod 600 -R /etc/wireguard/

	SERVER_PRIV_KEY=$(wg genkey)
	SERVER_PUB_KEY=$(wg pubkey)

	# Сохранить настройки WireGuard
	echo "SERVER_PUB_IP=${SERVER_PUB_IP}
SERVER_PUB_NIC=${SERVER_PUB_NIC}
SERVER_WG_NIC=${SERVER_WG_NIC}
SERVER_WG_IPV4=${SERVER_WG_IPV4}
SERVER_PORT=${SERVER_PORT}
SERVER_PRIV_KEY=${SERVER_PRIV_KEY}
SERVER_PUB_KEY=${SERVER_PUB_KEY}
CLIENT_DNS=${CLIENT_DNS}" >/etc/wireguard/params

	# Добавить интерфейс сервера
	echo "[Interface]
PrivateKey = ${SERVER_PRIV_KEY}
Address = ${SERVER_WG_IPV4}/24
ListenPort = ${SERVER_PORT}
PostUp = iptables -A FORWARD -i %i -j ACCEPT; iptables -t nat -A POSTROUTING -o ${SERVER_PUB_NIC} -j MASQUERADE
PostDown = iptables -D FORWARD -i %i -j ACCEPT; iptables -t nat -D POSTROUTING -o ${SERVER_PUB_NIC} -j MASQUERADE" >"/etc/wireguard/${SERVER_WG_NIC}.conf"


	# Включить маршрутизацию на сервере
	echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf

	sysctl -p

	systemctl enable "wg-quick@${SERVER_WG_NIC}.service"
	systemctl start "wg-quick@${SERVER_WG_NIC}.service"
	systemctl status "wg-quick@${SERVER_WG_NIC}.service"

	newClient
	echo "Если вы хотите добавить больше клиентов, Вам просто нужно запустить этот скрипт еще раз!"

	# Проверьте, работает ли WireGuard
	systemctl is-active --quiet "wg-quick@${SERVER_WG_NIC}"
	WG_RUNNING=$?

	# WireGuard может не работать, если мы обновим ядро. Сообщите пользователю о перезагрузке
	if [[ ${WG_RUNNING} -ne 0 ]]; then
		echo -e "\n${RED}ПРЕДУПРЕЖДЕНИЕ: WireGuard не работает.${NC}"
		echo -e "${ORANGE}Вы можете проверить, работает ли WireGuard, с помощью: systemctl status wg-quick@${SERVER_WG_NIC}${NC}"
		echo -e "${ORANGE}Если вы получите что-то вроде \"Cannot find device ${SERVER_WG_NIC}\", пожалуйста перезагрузите!${NC}"
	fi
}

function newClient() {
	ENDPOINT="${SERVER_PUB_IP}:${SERVER_PORT}"

	echo ""
	echo "Напишите имя клиента."
	echo "Имя должно состоять из буквенно-цифровых символов. Он также может включать подчеркивание или тире и не может превышать 15 символов."

	until [[ ${CLIENT_NAME} =~ ^[a-zA-Z0-9_-]+$ && ${CLIENT_EXISTS} == '0' && ${#CLIENT_NAME} -lt 16 ]]; do
		read -rp "Имя клиента: " -e CLIENT_NAME
		CLIENT_EXISTS=$(grep -c -E "^### Клиент ${CLIENT_NAME}\$" "/etc/wireguard/${SERVER_WG_NIC}.conf")

		if [[ ${CLIENT_EXISTS} == '1' ]]; then
			echo ""
			echo "Клиент с указанным именем уже создан, выберите другое имя."
			echo ""
		fi
	done

	for DOT_IP in {2..254}; do
		DOT_EXISTS=$(grep -c "${SERVER_WG_IPV4::-1}${DOT_IP}" "/etc/wireguard/${SERVER_WG_NIC}.conf")
		if [[ ${DOT_EXISTS} == '0' ]]; then
			break
		fi
	done

	if [[ ${DOT_EXISTS} == '1' ]]; then
		echo ""
		echo "Настроенная подсеть поддерживает только 253 клиента."
		exit 1
	fi

	BASE_IP=$(echo "$SERVER_WG_IPV4" | awk -F '.' '{ print $1"."$2"."$3 }')
	until [[ ${IPV4_EXISTS} == '0' ]]; do
		read -rp "IPv4 клиента WireGuard: ${BASE_IP}." -e -i "${DOT_IP}" DOT_IP
		CLIENT_WG_IPV4="${BASE_IP}.${DOT_IP}"
		IPV4_EXISTS=$(grep -c "$CLIENT_WG_IPV4/24" "/etc/wireguard/${SERVER_WG_NIC}.conf")

		if [[ ${IPV4_EXISTS} == '1' ]]; then
			echo ""
			echo "Клиент с указанным IPv4 уже создан, выберите другой IPv4."
			echo ""
		fi
	done

	# Сгенерировать пару ключей для клиента
	CLIENT_PRIV_KEY=$(wg genkey)
	CLIENT_PUB_KEY=$(wg pubkey)
	CLIENT_PRE_SHARED_KEY=$(wg genpsk)

	# Домашняя директория пользователя, куда будет записана конфигурация клиента
	if [ -e "/home/${CLIENT_NAME}" ]; then
		# если $1 имя пользователя
		HOME_DIR="/home/${CLIENT_NAME}"
	elif [ "${SUDO_USER}" ]; then
		# если нет, использовать SUDO_USER
		if [ "${SUDO_USER}" == "root" ]; then
			# Если запустить sudo как root
			HOME_DIR="/root"
		else
			HOME_DIR="/home/${SUDO_USER}"
		fi
	else
		# если нет SUDO_USER, использовать /root
		HOME_DIR="/root"
	fi

	# Создайте клиентский файл и добавьте сервер в качестве пира.
	echo "[Interface]
PrivateKey = ${CLIENT_PRIV_KEY}
ListenPort = ${SERVER_PORT}
Address = ${CLIENT_WG_IPV4}/32
DNS = ${CLIENT_DNS}

[Peer]
PublicKey = ${SERVER_PUB_KEY}
Endpoint = ${ENDPOINT}
AllowedIPs = 0.0.0.0/0" >>"${HOME_DIR}/${SERVER_WG_NIC}-client-${CLIENT_NAME}.conf"

	echo -e "\n### Клиент ${CLIENT_NAME}
[Peer]
PublicKey = ${CLIENT_PUB_KEY}
AllowedIPs = ${CLIENT_WG_IPV4}/32" >>"/etc/wireguard/${SERVER_WG_NIC}.conf"

#PresharedKey = ${CLIENT_PRE_SHARED_KEY}

	# перезапустить wireguard, чтобы применить изменения
	wg syncconf "${SERVER_WG_NIC}" <(wg-quick strip "${SERVER_WG_NIC}")

	echo -e "\nВот ваш файл конфигурации клиента в виде QR-кода:"

	qrencode -t ansiutf8 -l L <"${HOME_DIR}/${SERVER_WG_NIC}-client-${CLIENT_NAME}.conf"

	echo "Он также доступен в ${HOME_DIR}/${SERVER_WG_NIC}-client-${CLIENT_NAME}.conf"
}

function revokeClient() {
	NUMBER_OF_CLIENTS=$(grep -c -E "^### Клиент" "/etc/wireguard/${SERVER_WG_NIC}.conf")
	if [[ ${NUMBER_OF_CLIENTS} == '0' ]]; then
		echo ""
		echo "У вас нет существующих клиентов!"
		exit 1
	fi

	echo ""
	echo "Выберите существующий клиент, который вы хотите удалить"
	grep -E "^### Клиент" "/etc/wireguard/${SERVER_WG_NIC}.conf" | cut -d ' ' -f 3 | nl -s ') '
	until [[ ${CLIENT_NUMBER} -ge 1 && ${CLIENT_NUMBER} -le ${NUMBER_OF_CLIENTS} ]]; do
		if [[ ${CLIENT_NUMBER} == '1' ]]; then
			read -rp "Выберите одного клиента [1]: " CLIENT_NUMBER
		else
			read -rp "Выберите одного клиента [1-${NUMBER_OF_CLIENTS}]: " CLIENT_NUMBER
		fi
	done

	# сопоставить выбранный номер с именем клиента
	CLIENT_NAME=$(grep -E "^### Клиент" "/etc/wireguard/${SERVER_WG_NIC}.conf" | cut -d ' ' -f 3 | sed -n "${CLIENT_NUMBER}"p)

	# удалить соответствие блока [Peer] $CLIENT_NAME
	sed -i "/^### Клиент ${CLIENT_NAME}\$/,/^$/d" "/etc/wireguard/${SERVER_WG_NIC}.conf"

	# удалить сгенерированный файл клиента
	rm -f "${HOME}/${SERVER_WG_NIC}-client-${CLIENT_NAME}.conf"

	# перезапустить wireguard, чтобы применить изменения
	wg syncconf "${SERVER_WG_NIC}" <(wg-quick strip "${SERVER_WG_NIC}")
}

function uninstallWg() {
	echo ""
	read -rp "Вы действительно хотите удалить WireGuard? [y/n]: " -e -i n REMOVE
	if [[ $REMOVE == 'y' ]]; then
		checkOS

		systemctl stop "wg-quick@${SERVER_WG_NIC}"
		systemctl disable "wg-quick@${SERVER_WG_NIC}"

		if [[ ${OS} == 'ubuntu' ]]; then
			apt-get autoremove --purge -y wireguard qrencode
		elif [[ ${OS} == 'debian' ]]; then
			apt-get autoremove --purge -y wireguard qrencode
		elif [[ ${OS} == 'fedora' ]]; then
			dnf remove -y wireguard-tools qrencode
			if [[ ${VERSION_ID} -lt 32 ]]; then
				dnf remove -y wireguard-dkms
				dnf copr disable -y jdoss/wireguard
			fi
			dnf autoremove -y
		elif [[ ${OS} == 'centos' ]]; then
			yum -y remove kmod-wireguard wireguard-tools qrencode
			yum -y autoremove
		elif [[ ${OS} == 'oracle' ]]; then
			yum -y remove wireguard-tools qrencode
			yum -y autoremove
		elif [[ ${OS} == 'arch' ]]; then
			pacman -Rs --noconfirm wireguard-tools qrencode
		fi

		rm -rf /etc/wireguard
		rm -f /etc/sysctl.d/wg.conf

		# Перезагрузить sysctl
		sysctl --system

		# Проверьте, работает ли WireGuard
		systemctl is-active --quiet "wg-quick@${SERVER_WG_NIC}"
		WG_RUNNING=$?

		if [[ ${WG_RUNNING} -eq 0 ]]; then
			echo "Не удалось правильно удалить WireGuard."
			exit 1
		else
			echo "WireGuard успешно удален."
			exit 0
		fi
	else
		echo ""
		echo "Удаление прервано!"
	fi
}

function manageMenu() {
	echo "Добро пожаловать в программу установки WireGuard!"
	echo "Репозиторий git доступен по адресу: https://github.com/iosconstantine/wireguard-installer."
	echo ""
	echo "Похоже, WireGuard уже установлен."
	echo ""
	echo "Что Вы хотите сделать?"
	echo "   1) Добавить нового пользователя"
	echo "   2) Удалить существующего пользователя"
	echo "   3) Удалить WireGuard"
	echo "   4) Выйти"
	until [[ ${MENU_OPTION} =~ ^[1-4]$ ]]; do
		read -rp "Выберите вариант [1-4]: " MENU_OPTION
	done
	case "${MENU_OPTION}" in
	1)
		newClient
		;;
	2)
		revokeClient
		;;
	3)
		uninstallWg
		;;
	4)
		exit 0
		;;
	esac
}

# Проверить наличие root, virt, OS...
initialCheck

# Проверяем, установлен ли WireGuard, и загружаем параметры
if [[ -e /etc/wireguard/params ]]; then
	source /etc/wireguard/params
	manageMenu
else
	installWireGuard
fi
