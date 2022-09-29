# WireGuard installer

![visitors](https://visitor-badge.glitch.me/badge?page_id=iosconstantine-wireguard)

**Этот проект представляет собой bash-скрипт, цель которого — как можно проще настроить [WireGuard](https://www.wireguard.com/) VPN на сервере Linux!**

Скрипт поддерживает только IPv4

## Применение

Скачайте и выполните скрипт. Отвечайте на вопросы по сценарию, и он позаботится обо всем остальном.

```bash
curl -O https://raw.githubusercontent.com/iosconstantine/wireguard-installer/master/wg-install.sh
chmod +x wg-install.sh
./wg-install.sh
```

## Требования

- Ubuntu >= 16.04
- Debian >= 10
- Fedora
- CentOS
- Arch Linux
- Oracle Linux


Он установит WireGuard (модуль ядра и инструменты) на сервер, настроит его, создаст службу systemd и файл конфигурации клиента.

Запустите скрипт еще раз, чтобы добавить или удалить клиентов!
