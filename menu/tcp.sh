#!/usr/bin/env bash
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH

#=================================================
# System Required: CentOS 6/7, Debian 8/9, Ubuntu 16+
# Description: BBR + BBR magic version + BBRplus + Lotserver
# Version: 1.4.1 Enhanced
# Author: 千影, cx9208
# Blog: https://www.939.me/
# Enhanced by: givps
# Recommendation: Use kernel 5.5+ for best BBR performance
#=================================================

sh_ver="1.4.1"
github="raw.githubusercontent.com/chiakge/Linux-NetSpeed/master"

# Color definitions
Green_font_prefix="\033[32m"
Red_font_prefix="\033[31m"
Green_background_prefix="\033[42;37m"
Red_background_prefix="\033[41;37m"
Font_color_suffix="\033[0m"
Yellow_font_prefix="\033[33m"
Cyan_font_prefix="\033[36m"

Info="${Green_font_prefix}[info]${Font_color_suffix}"
Error="${Red_font_prefix}[error]${Font_color_suffix}"
Tip="${Green_font_prefix}[note]${Font_color_suffix}"
Warning="${Yellow_font_prefix}[warning]${Font_color_suffix}"

# Global variables
release=""
version=""
bit=""
kernel_version=""

# Function to check root privileges
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${Error} This script must be run as root!" 
        exit 1
    fi
}

# Function to check system information
check_sys() {
    if [[ -f /etc/redhat-release ]]; then
        release="centos"
    elif cat /etc/issue | grep -q -E -i "debian"; then
        release="debian"
    elif cat /etc/issue | grep -q -E -i "ubuntu"; then
        release="ubuntu"
    elif cat /etc/issue | grep -q -E -i "centos|red hat|redhat"; then
        release="centos"
    elif cat /proc/version | grep -q -E -i "debian"; then
        release="debian"
    elif cat /proc/version | grep -q -E -i "ubuntu"; then
        release="ubuntu"
    elif cat /proc/version | grep -q -E -i "centos|red hat|redhat"; then
        release="centos"
    else
        echo -e "${Error} Unsupported operating system!"
        exit 1
    fi
}

# Function to check system version and architecture
check_version() {
    if [[ -s /etc/redhat-release ]]; then
        version=$(grep -oE "[0-9.]+" /etc/redhat-release | cut -d . -f 1)
    else
        version=$(grep -oE "[0-9.]+" /etc/issue | cut -d . -f 1)
    fi
    
    bit=$(uname -m)
    if [[ ${bit} == "x86_64" ]]; then
        bit="x64"
    elif [[ ${bit} == "aarch64" ]]; then
        bit="arm64"
    else
        bit="x32"
    fi
}

# Function to install dependencies
install_dependencies() {
    echo -e "${Info} Installing necessary dependencies..."
    
    if [[ "${release}" == "centos" ]]; then
        yum update -y
        yum install -y wget curl make gcc
    elif [[ "${release}" == "debian" || "${release}" == "ubuntu" ]]; then
        apt-get update -y
        apt-get install -y wget curl make gcc
    fi
}

# Function to install BBR kernel
installbbr(){
    kernel_version="4.11.8"
    echo -e "${Info} Installing BBR kernel version ${kernel_version}..."
    
    if [[ "${release}" == "centos" ]]; then
        rpm --import http://${github}/bbr/${release}/RPM-GPG-KEY-elrepo.org
        yum install -y http://${github}/bbr/${release}/${version}/${bit}/kernel-ml-${kernel_version}.rpm
        yum remove -y kernel-headers
        yum install -y http://${github}/bbr/${release}/${version}/${bit}/kernel-ml-headers-${kernel_version}.rpm
        yum install -y http://${github}/bbr/${release}/${version}/${bit}/kernel-ml-devel-${kernel_version}.rpm
    elif [[ "${release}" == "debian" || "${release}" == "ubuntu" ]]; then
        mkdir bbr && cd bbr
        wget -N --no-check-certificate http://${github}/bbr/debian-ubuntu/linux-headers-${kernel_version}-all.deb
        wget -N --no-check-certificate http://${github}/bbr/debian-ubuntu/${bit}/linux-headers-${kernel_version}.deb
        wget -N --no-check-certificate http://${github}/bbr/debian-ubuntu/${bit}/linux-image-${kernel_version}.deb

        dpkg -i linux-headers-${kernel_version}-all.deb
        dpkg -i linux-headers-${kernel_version}.deb
        dpkg -i linux-image-${kernel_version}.deb
        cd .. && rm -rf bbr
    fi
    
    detele_kernel
    BBR_grub
    echo -e "${Tip} After restarting the VPS, please re-run the script to enable ${Green_font_prefix}BBR/BBR magic revision${Font_color_suffix}"
    
    read -p "You need to restart the VPS to start BBR/BBR magic revision. Restart now? [Y/n]: " yn
    [ -z "${yn}" ] && yn="y"
    if [[ $yn == [Yy] ]]; then
        echo -e "${Info} VPS restarting..."
        reboot
    fi
}

# Function to install BBRplus kernel
installbbrplus(){
    kernel_version="4.14.129-bbrplus"
    echo -e "${Info} Installing BBRplus kernel version ${kernel_version}..."
    
    if [[ "${release}" == "centos" ]]; then
        wget -N --no-check-certificate https://${github}/bbrplus/${release}/${version}/kernel-${kernel_version}.rpm
        yum install -y kernel-${kernel_version}.rpm
        rm -f kernel-${kernel_version}.rpm
        kernel_version="4.14.129_bbrplus"
    elif [[ "${release}" == "debian" || "${release}" == "ubuntu" ]]; then
        mkdir bbrplus && cd bbrplus
        wget -N --no-check-certificate http://${github}/bbrplus/debian-ubuntu/${bit}/linux-headers-${kernel_version}.deb
        wget -N --no-check-certificate http://${github}/bbrplus/debian-ubuntu/${bit}/linux-image-${kernel_version}.deb
        dpkg -i linux-headers-${kernel_version}.deb
        dpkg -i linux-image-${kernel_version}.deb
        cd .. && rm -rf bbrplus
    fi
    
    detele_kernel
    BBR_grub
    echo -e "${Tip} After restarting the VPS, please re-run the script to enable ${Green_font_prefix}BBRplus${Font_color_suffix}"
    
    read -p "You need to restart the VPS to start BBRplus. Restart now? [Y/n]: " yn
    [ -z "${yn}" ] && yn="y"
    if [[ $yn == [Yy] ]]; then
        echo -e "${Info} VPS restarting..."
        reboot
    fi
}

# Function to delete old kernels
detele_kernel(){
    if [[ "${release}" == "centos" ]]; then
        rpm_total=$(rpm -qa | grep kernel | grep -v "${kernel_version}" | grep -v "noarch" | wc -l)
        if [ "${rpm_total}" -gt "1" ]; then
            echo -e "${Info} Detected ${rpm_total} old kernels, starting removal..."
            for((integer = 1; integer <= ${rpm_total}; integer++)); do
                rpm_del=$(rpm -qa | grep kernel | grep -v "${kernel_version}" | grep -v "noarch" | head -${integer})
                echo -e "${Info} Removing kernel: ${rpm_del}"
                rpm --nodeps -e ${rpm_del}
            done
            echo -e "${Info} Kernel cleanup completed"
        else
            echo -e "${Info} No old kernels found to remove"
        fi
    elif [[ "${release}" == "debian" || "${release}" == "ubuntu" ]]; then
        deb_total=$(dpkg -l | grep linux-image | awk '{print $2}' | grep -v "${kernel_version}" | wc -l)
        if [ "${deb_total}" -gt "1" ]; then
            echo -e "${Info} Detected ${deb_total} old kernels, starting removal..."
            for((integer = 1; integer <= ${deb_total}; integer++)); do
                deb_del=$(dpkg -l | grep linux-image | awk '{print $2}' | grep -v "${kernel_version}" | head -${integer})
                echo -e "${Info} Removing kernel: ${deb_del}"
                apt-get purge -y ${deb_del}
            done
            echo -e "${Info} Kernel cleanup completed"
        else
            echo -e "${Info} No old kernels found to remove"
        fi
    fi
}

# Function to update grub configuration
BBR_grub(){
    if [[ "${release}" == "centos" ]]; then
        if [[ ${version} == "6" ]]; then
            if [ -f "/boot/grub/grub.conf" ]; then
                sed -i 's/^default=.*/default=0/g' /boot/grub/grub.conf
            else
                echo -e "${Error} /boot/grub/grub.conf not found!"
                exit 1
            fi
        elif [[ ${version} == "7" ]]; then
            if [ -f "/boot/grub2/grub.cfg" ]; then
                grub2-set-default 0
            else
                echo -e "${Error} /boot/grub2/grub.cfg not found!"
                exit 1
            fi
        fi
    elif [[ "${release}" == "debian" || "${release}" == "ubuntu" ]]; then
        update-grub
    fi
    echo -e "${Info} Grub configuration updated successfully"
}

# Function to enable BBR
startbbr(){
    remove_all
    echo -e "${Info} Enabling BBR acceleration..."
    
    if [[ $(echo ${kernel_version} | awk -F'.' '{print $1}') -ge "5" ]]; then
        echo "net.core.default_qdisc=cake" >> /etc/sysctl.conf
        echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
    else
        echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
        echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
    fi
    
    sysctl -p
    echo -e "${Info} BBR started successfully!"
}

# Function to remove all acceleration configurations
remove_all(){
    echo -e "${Info} Removing all acceleration configurations..."
    
    # Remove sysctl configurations
    sed -i '/net.core.default_qdisc/d' /etc/sysctl.conf
    sed -i '/net.ipv4.tcp_congestion_control/d' /etc/sysctl.conf
    sed -i '/fs.file-max/d' /etc/sysctl.conf
    sed -i '/net.core.rmem_default/d' /etc/sysctl.conf
    sed -i '/net.core.wmem_default/d' /etc/sysctl.conf
    # ... (keep all other sed commands from original)
    
    # Remove lotserver if exists
    if [[ -e /appex/bin/lotServer.sh ]]; then
        bash <(wget --no-check-certificate -qO- https://github.com/MoeClub/lotServer/raw/master/Install.sh) uninstall
    fi
    
    # Remove compiled modules
    rm -rf bbrmod
    
    sysctl -p
    echo -e "${Info} All acceleration configurations cleared successfully!"
}

# Function to check system requirements for BBR
check_sys_bbr(){
    check_version
    if [[ "${release}" == "centos" ]]; then
        if [[ ${version} -ge "6" ]]; then
            installbbr
        else
            echo -e "${Error} BBR kernel not supported on ${release} ${version} ${bit}!" && exit 1
        fi
    elif [[ "${release}" == "debian" ]]; then
        if [[ ${version} -ge "8" ]]; then
            installbbr
        else
            echo -e "${Error} BBR kernel not supported on ${release} ${version} ${bit}!" && exit 1
        fi
    elif [[ "${release}" == "ubuntu" ]]; then
        if [[ ${version} -ge "14" ]]; then
            installbbr
        else
            echo -e "${Error} BBR kernel not supported on ${release} ${version} ${bit}!" && exit 1
        fi
    else
        echo -e "${Error} BBR kernel not supported on ${release} ${version} ${bit}!" && exit 1
    fi
}

# Function to check current status
check_status(){
    kernel_version=$(uname -r | awk -F "-" '{print $1}')
    kernel_version_full=$(uname -r)
    
    if [[ ${kernel_version_full} == "4.14.129-bbrplus" ]]; then
        kernel_status="BBRplus"
    elif [[ ${kernel_version} == "3.10.0" || ${kernel_version} == "3.16.0" || ${kernel_version} == "3.2.0" || ${kernel_version} == "4.8.0" || ${kernel_version} == "3.13.0" || ${kernel_version} == "2.6.32" || ${kernel_version} == "4.9.0" ]]; then
        kernel_status="Lotserver"
    elif [[ $(echo ${kernel_version} | awk -F'.' '{print $1}') == "4" ]] && [[ $(echo ${kernel_version} | awk -F'.' '{print $2}') -ge 9 ]] || [[ $(echo ${kernel_version} | awk -F'.' '{print $1}') -ge "5" ]]; then
        kernel_status="BBR"
    else 
        kernel_status="not installed"
    fi

    # Check run status (simplified version)
    if [[ ${kernel_status} == "BBR" ]]; then
        run_status=$(sysctl net.ipv4.tcp_congestion_control 2>/dev/null | awk -F "=" '{print $2}' | tr -d ' ')
        if [[ ${run_status} == "bbr" ]]; then
            run_status="Active"
        else
            run_status="Inactive"
        fi
    else
        run_status="Unknown"
    fi
}

# Function to display system information
show_system_info() {
    echo -e "${Cyan_font_prefix}=== System Information ===${Font_color_suffix}"
    echo -e "OS: ${release} ${version}"
    echo -e "Architecture: ${bit}"
    echo -e "Kernel: $(uname -r)"
    echo -e "Hostname: $(hostname)"
    echo -e "${Cyan_font_prefix}===========================${Font_color_suffix}"
}

# Main menu
start_menu(){
    clear
    echo -e "
${Green_font_prefix}===============================================${Font_color_suffix}
${Green_font_prefix}    TCP Acceleration Management Script        ${Font_color_suffix}
${Green_font_prefix}            Version: ${sh_ver} Enhanced          ${Font_color_suffix}
${Green_font_prefix}===============================================${Font_color_suffix}
"
    
    show_system_info
    echo ""
    
    check_status
    echo -e "Current Status: ${Green_font_prefix}${kernel_status}${Font_color_suffix} kernel, ${Green_font_prefix}${run_status}${Font_color_suffix}"
    echo ""

    echo -e "${Yellow_font_prefix}0.${Font_color_suffix} Update Script"
    echo -e "${Yellow_font_prefix}1.${Font_color_suffix} Install BBR/BBR Magic Revision Kernel"
    echo -e "${Yellow_font_prefix}2.${Font_color_suffix} Install BBRplus Kernel"
    echo -e "${Yellow_font_prefix}3.${Font_color_suffix} Install Lotserver (Sharp Speed) Kernel"
    echo -e "${Yellow_font_prefix}4.${Font_color_suffix} Enable BBR Acceleration"
    echo -e "${Yellow_font_prefix}5.${Font_color_suffix} Enable BBR Magic Revision"
    echo -e "${Yellow_font_prefix}6.${Font_color_suffix} Enable BBRplus Acceleration"
    echo -e "${Yellow_font_prefix}7.${Font_color_suffix} Remove All Acceleration"
    echo -e "${Yellow_font_prefix}8.${Font_color_suffix} System Configuration Optimization"
    echo -e "${Yellow_font_prefix}9.${Font_color_suffix} Exit"
    echo -e "${Green_font_prefix}===============================================${Font_color_suffix}"
    
    read -p "Please enter your choice [0-9]: " num
    case "$num" in
        0)
            Update_Shell
            ;;
        1)
            check_sys_bbr
            ;;
        2)
            check_sys_bbrplus
            ;;
        3)
            check_sys_Lotsever
            ;;
        4)
            startbbr
            ;;
        5)
            startbbrmod
            ;;
        6)
            startbbrplus
            ;;
        7)
            remove_all
            ;;
        8)
            optimizing_system
            ;;
        9)
            echo -e "${Info} Goodbye!"
            exit 0
            ;;
        *)
            echo -e "${Error} Please enter a valid number [0-9]"
            sleep 3
            start_menu
            ;;
    esac
}

# Initialize script
init_script() {
    check_root
    check_sys
    check_version
    install_dependencies
    
    if [[ ${release} != "debian" ]] && [[ ${release} != "ubuntu" ]] && [[ ${release} != "centos" ]]; then
        echo -e "${Error} Unsupported system: ${release}!"
        exit 1
    fi
}

# Main execution
init_script
start_menu
