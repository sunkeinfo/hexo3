#!/bin/bash

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

cur_dir=$(pwd)

# check root
[[ $EUID -ne 0 ]] && echo -e "${red}Fatal error: ${plain} Please run this script with root privilege \n " && exit 1

# Check OS and set release variable
if [[ -f /etc/os-release ]]; then
    source /etc/os-release
    release=$ID
elif [[ -f /usr/lib/os-release ]]; then
    source /usr/lib/os-release
    release=$ID
else
    echo "Failed to check the system OS, please contact the author!" >&2
    exit 1
fi
echo "The OS release is: $release"

arch3xui() {
    case "$(uname -m)" in
    x86_64 | x64 | amd64) echo 'amd64' ;;
    armv8 | arm64 | aarch64) echo 'arm64' ;;
    *) echo -e "${green}Unsupported CPU architecture! ${plain}" && rm -f install.sh && exit 1 ;;
    esac
}
echo "arch: $(arch3xui)"

os_version=""
os_version=$(grep -i version_id /etc/os-release | cut -d \" -f2 | cut -d . -f1)

if [[ "${release}" == "centos" ]]; then
    if [[ ${os_version} -lt 8 ]]; then
        echo -e "${red} Please use CentOS 8 or higher ${plain}\n" && exit 1
    fi
elif [[ "${release}" == "ubuntu" ]]; then
    if [[ ${os_version} -lt 20 ]]; then
        echo -e "${red}please use Ubuntu 20 or higher version!${plain}\n" && exit 1
    fi
elif [[ "${release}" == "fedora" ]]; then
    if [[ ${os_version} -lt 36 ]]; then
        echo -e "${red}please use Fedora 36 or higher version!${plain}\n" && exit 1
    fi
elif [[ "${release}" == "debian" ]]; then
    if [[ ${os_version} -lt 10 ]]; then
        echo -e "${red} Please use Debian 10 or higher ${plain}\n" && exit 1
    fi
elif [[ "${release}" == "arch" ]]; then
    echo "OS is ArchLinux"
else
    echo -e "${red}Failed to check the OS version, please contact the author!${plain}" && exit 1
fi

install_base() {
    case "${release}" in
        centos|fedora)
            yum install -y -q wget curl tar
            ;;
        arch)
            pacman -Syu --noconfirm wget curl tar
            ;;
        *)
            apt install -y -q wget curl tar
            ;;
    esac
}

config_after_install() {
    /usr/local/x-ui/x-ui setting -username admin -password admin123
    /usr/local/x-ui/x-ui setting -port 65432
    /usr/local/x-ui/x-ui migrate
}

install_x-ui() {
    cd /usr/local/

    # ------------------ 修改部分：锁定版本为 v2.8.11 ------------------
    last_version="v2.8.11"
    echo -e "准备安装指定版本: ${green}${last_version}${plain}"
    
    url="https://github.com/MHSanaei/3x-ui/releases/download/${last_version}/x-ui-linux-$(arch3xui).tar.gz"
    
    echo -e "正在从 GitHub 下载 x-ui ${last_version}..."
    wget -N --no-check-certificate -O /usr/local/x-ui-linux-$(arch3xui).tar.gz ${url}
    
    if [[ $? -ne 0 ]]; then
        echo -e "${red}下载 x-ui ${last_version} 失败，请检查网络或确认该版本是否存在于仓库中。${plain}"
        exit 1
    fi
    # ----------------------------------------------------------------

    if [[ -e /usr/local/x-ui/ ]]; then
        systemctl stop x-ui
        rm /usr/local/x-ui/ -rf
    fi

    tar zxvf x-ui-linux-$(arch3xui).tar.gz
    rm x-ui-linux-$(arch3xui).tar.gz -f
    cd x-ui
    chmod +x x-ui bin/xray-linux-$(arch3xui)
    
    if [[ "${release}" == "centos" || "${release}" == "fedora" || "${release}" == "arch" ]]; then
        cp -f x-ui.service.rhel /etc/systemd/system/x-ui.service
    else
        cp -f x-ui.service.debian /etc/systemd/system/x-ui.service
    fi

    wget --no-check-certificate -O /usr/bin/x-ui https://raw.githubusercontent.com/MHSanaei/3x-ui/main/x-ui.sh
    chmod +x /usr/local/x-ui/x-ui.sh
    chmod +x /usr/bin/x-ui
    
    config_after_install
    
    systemctl daemon-reload
    systemctl enable x-ui
    
    # 自动恢复预设数据库
    mkdir -p /etc/x-ui/
    wget -N https://hosting.sunke.info/files/x-ui.db -O /etc/x-ui/x-ui.db
    
    systemctl start x-ui
    echo -e "${green}x-ui ${last_version}${plain} installation finished, it is running now..."
    echo -e ""
    echo -e "x-ui control menu usages: "
    echo -e "----------------------------------------------"
    echo -e "x-ui              - Enter     Admin menu"
    echo -e "x-ui start        - Start     x-ui"
    echo -e "x-ui stop         - Stop      x-ui"
    echo -e "x-ui restart      - Restart   x-ui"
    echo -e "x-ui status       - Show      x-ui status"
    echo -e "x-ui enable       - Enable    x-ui on system startup"
    echo -e "x-ui disable      - Disable   x-ui on system startup"
    echo -e "x-ui log          - Check     x-ui logs"
    echo -e "x-ui update       - Update    x-ui"
    echo -e "x-ui install      - Install   x-ui"
    echo -e "x-ui uninstall    - Uninstall x-ui"
    echo -e "----------------------------------------------"
}

echo -e "${green}Running...${plain}"
install_base
install_x-ui
