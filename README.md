# QUICK START
## 1. Install
```bash
curl -s https://api.github.com/repos/phonevox/pzabbix/releases/latest | grep '"tag_name":' | sed 's/.*"tag_name": "\(.*\)",/\1/' | xargs -I {} curl -skL https://github.com/phonevox/pzabbix/archive/refs/tags/{}.tar.gz | tar xz --transform="s,^[^/]*,pzabbix,"
```
## 2. Run
```bash
./pzabbix --help #explains everything
./pzabbix -S <zabbix_server_url> #assumes zabbix server and active server. assumes hostname is machineid or specific provider. inserts metadata automatically
./pzabbix -s <server> -sa <active_server> -H <hostname> [-p <provider_location>]
```