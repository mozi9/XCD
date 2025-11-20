#!/bin/bash

# =============================================================================
# Android内核构建脚本
# 版本: 1.0
# 描述: 支持多设备、多系统的内核构建，集成KernelSU和附加功能
# 兼容: GitHub Actions工作流和本地构建
# =============================================================================

# 颜色定义
yellow='\033[0;33m'
white='\033[0m'
red='\033[0;31m'
green='\033[0;32m'
blue='\033[0;34m'
purple='\033[0;35m'
cyan='\033[0;36m'

# 输出带颜色的消息函数
color_echo() {
    local color=$1
    shift
    echo -e "${color}$*${white}"
}

# 打印分隔线
print_separator() {
    color_echo "$cyan" "=============================================="
}

# 打印步骤标题
print_step() {
    local step_name="$1"
    print_separator
    color_echo "$green" "$step_name"
    print_separator
}

# 错误处理函数
error_exit() {
    color_echo "$red" "错误: $1"
    exit 1
}

# 警告函数
print_warning() {
    color_echo "$yellow" "警告: $1"
}

# 成功函数
print_success() {
    color_echo "$green" "✓ $1"
}

# 信息函数
print_info() {
    color_echo "$blue" "ℹ $1"
}

# 确保脚本在出错时退出
set -e

# --- 动态定位脚本目录 ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR" || {
    error_exit "无法切换到脚本所在目录: $SCRIPT_DIR"
}
print_success "工作目录: $SCRIPT_DIR"

# --- 安全的make调用函数 ---
safe_make() {
    local target="$1"
    local num_jobs=$(nproc)
    
    print_info "执行编译命令..."
    print_info "工作目录: $(pwd)"
    print_info "构建目录: $BUILD_DIR"
    print_info "线程数: $num_jobs"
    
    # 构建基本make命令
    local base_cmd=(
        "make"
        "O=$BUILD_DIR"
        "ARCH=arm64"
        "SUBARCH=arm64"
        "CC=clang"
        "LD=ld.lld"
        "CROSS_COMPILE=aarch64-linux-gnu-"
        "CROSS_COMPILE_ARM32=arm-linux-gnueabi-"
        "CLANG_TRIPLE=aarch64-linux-gnu-"
        "AR=llvm-ar"
        "NM=llvm-nm"
        "STRIP=llvm-strip"
        "OBJCOPY=llvm-objcopy"
        "OBJDUMP=llvm-objdump"
        "-j$num_jobs"
    )
    
    # 添加目标（如果有）
    if [ -n "$target" ]; then
        base_cmd+=("$target")
        print_info "编译目标: $target"
    else
        print_info "编译目标: <默认目标>"
    fi
    
    # 添加额外的make flags
    if [ -n "$MAKE_FLAGS" ]; then
        IFS=' ' read -r -a extra_flags <<< "$MAKE_FLAGS"
        base_cmd+=("${extra_flags[@]}")
        print_info "额外参数: $MAKE_FLAGS"
    fi
    
    # 显示完整命令
    color_echo "$cyan" "完整命令: ${base_cmd[*]}"
    
    # 执行编译命令
    if "${base_cmd[@]}"; then
        print_success "编译成功完成"
        return 0
    else
        error_exit "编译失败"
    fi
}

# --- 参数解析增强 ---
print_step "参数解析"

# 初始化变量
TARGET_DEVICE=""
KSU_VERSION=""
ADDITIONAL=""
TARGET_SYSTEM="MIUI"  # 默认值匹配GitHub Actions
CCACHE_ENABLED=true
NO_CLEAN=false
MAKE_FLAGS=""
SHOW_HELP=false

# 显示使用说明
show_usage() {
    color_echo "$yellow" "用法: $0 <设备名称> [选项]"
    color_echo "$yellow" "选项:"
    color_echo "$yellow" "  --ksu <类型>        KernelSU类型: ksu, rksu, sukisu, sukisu-ultra, noksu"
    color_echo "$yellow" "  --additional <功能> 附加功能: no, susfs, kpm, susfs-kpm"
    color_echo "$yellow" "  --system <系统>     目标系统: aosp, miui, all"
    color_echo "$yellow" "  --noccache         禁用ccache"
    color_echo "$yellow" "  --noclean          跳过清理步骤"
    color_echo "$yellow" "  --make-flags <参数> 传递额外参数给make"
    color_echo "$yellow" "  --help             显示此帮助信息"
    echo
    color_echo "$yellow" "示例:"
    color_echo "$yellow" "  $0 alioth --ksu sukisu-ultra --additional susfs-kpm --system miui"
    color_echo "$yellow" "  $0 munch --ksu noksu --system aosp --noccache"
    echo
    color_echo "$yellow" "可用设备:"
    if [[ -d "$SCRIPT_DIR/arch/arm64/configs" ]]; then
        ls "$SCRIPT_DIR/arch/arm64/configs/"*_defconfig 2>/dev/null | 
            sed "s|.*/||; s|_defconfig||" | xargs printf "  %s\n" || 
            color_echo "$red" "  无法读取设备配置目录"
    else
        color_echo "$red" "  配置目录不存在: $SCRIPT_DIR/arch/arm64/configs/"
    fi
}

# 解析参数
if [ $# -lt 1 ]; then
    error_exit "未指定目标设备"
fi

# 检查帮助参数
for arg in "$@"; do
    if [[ "$arg" == "--help" || "$arg" == "-h" ]]; then
        SHOW_HELP=true
        break
    fi
done

if $SHOW_HELP; then
    show_usage
    exit 0
fi

# 第一个参数是设备名称
TARGET_DEVICE="$1"
shift

# 处理选项参数
while [ $# -gt 0 ]; do
    case "$1" in
        --ksu)
            if [ -z "$2" ]; then
                error_exit "选项 --ksu 需要参数值"
            fi
            KSU_VERSION="$2"
            print_info "KernelSU版本: $KSU_VERSION"
            shift 2
            ;;
        --additional)
            if [ -z "$2" ]; then
                error_exit "选项 --additional 需要参数值"
            fi
            ADDITIONAL="$2"
            print_info "附加功能: $ADDITIONAL"
            shift 2
            ;;
        --system)
            if [ -z "$2" ]; then
                error_exit "选项 --system 需要参数值"
            fi
            TARGET_SYSTEM="$2"
            print_info "目标系统: $TARGET_SYSTEM"
            shift 2
            ;;
        --noccache)
            CCACHE_ENABLED=false
            print_info "禁用ccache"
            shift
            ;;
        --noclean)
            NO_CLEAN=true
            print_info "跳过清理步骤"
            shift
            ;;
        --make-flags)
            shift
            if [ -z "$1" ]; then
                error_exit "选项 --make-flags 需要参数值"
            fi
            MAKE_FLAGS="$*"
            # 清理MAKE_FLAGS中的潜在问题
            MAKE_FLAGS=$(echo "$MAKE_FLAGS" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
            print_info "Make额外参数: $MAKE_FLAGS"
            break
            ;;
        *)
            print_warning "忽略未知选项: $1"
            shift
            ;;
    esac
done

# 验证必需参数
if [ -z "$TARGET_DEVICE" ]; then
    error_exit "目标设备不能为空"
fi

# 验证系统参数
case "$TARGET_SYSTEM" in
    "aosp"|"miui"|"all") ;;
    *) error_exit "不支持的系统类型: $TARGET_SYSTEM (支持: aosp, miui, all)" ;;
esac

# 验证KSU参数
if [ -n "$KSU_VERSION" ]; then
    case "$KSU_VERSION" in
        "ksu"|"rksu"|"sukisu"|"sukisu-ultra"|"noksu") ;;
        *) error_exit "不支持的KernelSU类型: $KSU_VERSION" ;;
    esac
fi

# 验证附加功能参数
if [ -n "$ADDITIONAL" ]; then
    case "$ADDITIONAL" in
        "no"|"susfs"|"kpm"|"susfs-kpm") ;;
        *) error_exit "不支持的附加功能: $ADDITIONAL" ;;
    esac
fi

print_success "参数解析完成"
# --- 构建目录管理 ---
print_step "构建目录设置"

GIT_COMMIT_ID=$(git rev-parse --short=8 HEAD 2>/dev/null || echo "unknown")
BUILD_DIR="../build_${TARGET_DEVICE}_${GIT_COMMIT_ID}"

# 如果启用了跳过清理，但构建目录不存在，则创建它
if $NO_CLEAN && [ ! -d "$BUILD_DIR" ]; then
    print_warning "构建目录不存在，将创建新目录"
    NO_CLEAN=false
fi

print_info "使用独立构建目录: $BUILD_DIR"
mkdir -p "$BUILD_DIR"

# --- 工具链和环境设置 ---
print_step "工具链配置"

# 优先使用环境变量中的工具链路径，否则使用默认路径
if [ -n "$TOOLCHAIN_PATH" ] && [ -d "$TOOLCHAIN_PATH" ]; then
    print_info "使用环境变量中的工具链路径: $TOOLCHAIN_PATH"
else
    TOOLCHAIN_PATH="/home/runner/ZyC-clang"
    print_info "使用默认工具链路径: $TOOLCHAIN_PATH"
fi

# 检查工具链目录是否存在
if [ ! -d "$TOOLCHAIN_PATH" ]; then
    print_warning "工具链路径不存在 [$TOOLCHAIN_PATH]，尝试自动查找..."
    
    # 尝试在常见位置查找工具链
    possible_paths=(
        "/home/runner/ZyC-clang"
        "/usr/local/ZyC-clang" 
        "/opt/ZyC-clang"
        "$SCRIPT_DIR/toolchain"
        "$SCRIPT_DIR/../toolchain"
    )
    
    found_toolchain=false
    for path in "${possible_paths[@]}"; do
        if [ -d "$path" ] && [ -f "$path/bin/clang" ]; then
            TOOLCHAIN_PATH="$path"
            found_toolchain=true
            print_success "找到工具链: $TOOLCHAIN_PATH"
            break
        fi
    done
    
    if ! $found_toolchain; then
        error_exit "未找到有效的工具链路径，请设置TOOLCHAIN_PATH环境变量"
    fi
else
    print_success "工具链路径验证通过"
fi

# 设置环境变量
export PATH="$TOOLCHAIN_PATH/bin:$PATH"
export TOOLCHAIN_PATH="$TOOLCHAIN_PATH"

# 检查必要的工具
print_info "检查编译工具..."
essential_tools=("clang" "clang++" "ld.lld" "llvm-ar")
missing_tools=()

for tool in "${essential_tools[@]}"; do
    if command -v "$tool" >/dev/null 2>&1; then
        tool_path=$(command -v "$tool")
        print_success "找到工具: $tool -> $tool_path"
    else
        missing_tools+=("$tool")
        print_warning "未找到工具: $tool"
    fi
done

if [ ${#missing_tools[@]} -gt 0 ]; then
    print_warning "缺少以下工具: ${missing_tools[*]}"
    print_info "尝试在工具链目录中查找..."
    
    for tool in "${missing_tools[@]}"; do
        tool_path="$TOOLCHAIN_PATH/bin/$tool"
        if [ -f "$tool_path" ]; then
            print_success "在工具链中找到: $tool_path"
            # 创建符号链接到临时目录
            temp_bin="/tmp/kernel_build_bin"
            mkdir -p "$temp_bin"
            ln -sf "$tool_path" "$temp_bin/$tool"
            export PATH="$temp_bin:$PATH"
        else
            error_exit "无法找到必需工具: $tool"
        fi
    done
fi

# 设置ccache
if $CCACHE_ENABLED; then
    print_step "CCache配置"
    
    # 设置ccache目录
    export CCACHE_DIR="${CCACHE_DIR:-$HOME/.cache/ccache_mikernel}"
    mkdir -p "$CCACHE_DIR"
    
    # 设置编译器包装
    export CC="ccache clang"
    export CXX="ccache clang++"
    export PATH="/usr/lib/ccache:$PATH"
    
    print_success "已启用 ccache"
    print_info "缓存目录: $CCACHE_DIR"
    
    # 显示ccache统计信息
    if command -v ccache >/dev/null 2>&1; then
        print_info "CCache统计信息:"
        ccache -s | head -10
    else
        print_warning "ccache命令未找到，但CCACHE_ENABLED=true，继续构建..."
    fi
else
    print_info "CCache已禁用"
fi

# 显示工具版本信息
print_step "工具版本检查"
print_info "Clang版本:"
clang --version | head -3 || error_exit "无法获取clang版本"

print_info "LLD版本:"
ld.lld --version | head -2 || error_exit "无法获取lld版本"

print_info "LLVM工具链版本:"
llvm-ar --version | head -1 || print_warning "无法获取llvm-ar版本"

# --- 功能变量初始化 ---
print_step "功能配置初始化"

KSU_ENABLE=$([[ -n "$KSU_VERSION" && "$KSU_VERSION" != "noksu" ]] && echo 1 || echo 0)
SuSFS_ENABLE=0
KPM_ENABLE=0
KSU_ZIP_STR="NoKernelSU"

# 处理附加功能
case "$ADDITIONAL" in
    "susfs-kpm")
        SuSFS_ENABLE=1
        KPM_ENABLE=1
        print_success "启用 SuSFS 和 KPM"
        ;;
    "susfs")
        SuSFS_ENABLE=1
        print_success "启用 SuSFS"
        ;;
    "kpm")
        KPM_ENABLE=1
        print_success "启用 KPM"
        ;;
    "no"|"")
        print_info "未启用附加功能"
        ;;
    *)
        print_warning "未知的附加功能: $ADDITIONAL，按未启用处理"
        ;;
esac

# 检查设备配置
print_step "设备配置验证"

if [[ ! -f "$SCRIPT_DIR/arch/arm64/configs/${TARGET_DEVICE}_defconfig" ]]; then
    error_exit "未找到目标设备 [$TARGET_DEVICE] 的配置"
    
    print_info "可用设备配置:"
    if [[ -d "$SCRIPT_DIR/arch/arm64/configs" ]]; then
        available_configs=$(ls "$SCRIPT_DIR/arch/arm64/configs/"*_defconfig 2>/dev/null | 
            sed "s|.*/||; s|_defconfig||" | tr '\n' ' ')
        if [ -n "$available_configs" ]; then
            print_info "可用的设备: $available_configs"
        else
            print_warning "配置目录为空"
        fi
    else
        print_warning "配置目录不存在: $SCRIPT_DIR/arch/arm64/configs/"
    fi
else
    print_success "找到设备配置: ${TARGET_DEVICE}_defconfig"
fi

# 显示构建配置摘要
print_step "构建配置摘要"
color_echo "$cyan" "目标设备:    $TARGET_DEVICE"
color_echo "$cyan" "目标系统:    $TARGET_SYSTEM"
color_echo "$cyan" "KernelSU:    $([ $KSU_ENABLE -eq 1 ] && echo "$KSU_VERSION" || echo "禁用")"
color_echo "$cyan" "附加功能:    ${ADDITIONAL:-无}"
color_echo "$cyan" "Git Commit:  $GIT_COMMIT_ID"
color_echo "$cyan" "构建目录:    $BUILD_DIR"
color_echo "$cyan" "工具链路径:  $TOOLCHAIN_PATH"
color_echo "$cyan" "CCache:      $($CCACHE_ENABLED && echo "启用" || echo "禁用")"
color_echo "$cyan" "跳过清理:    $($NO_CLEAN && echo "是" || echo "否")"
color_echo "$cyan" "SuSFS:       $([ $SuSFS_ENABLE -eq 1 ] && echo "启用" || echo "禁用")"
color_echo "$cyan" "KPM:         $([ $KPM_ENABLE -eq 1 ] && echo "启用" || echo "禁用")"

if [ -n "$MAKE_FLAGS" ]; then
    color_echo "$cyan" "Make参数:    $MAKE_FLAGS"
fi

print_separator

# 基本make参数 - 使用数组更安全
MAKE_ARGS=()
MAKE_ARGS+=("O=$BUILD_DIR")
MAKE_ARGS+=("ARCH=arm64") 
MAKE_ARGS+=("SUBARCH=arm64")
MAKE_ARGS+=("CC=clang")
MAKE_ARGS+=("LD=ld.lld")
MAKE_ARGS+=("CROSS_COMPILE=aarch64-linux-gnu-")
MAKE_ARGS+=("CROSS_COMPILE_ARM32=arm-linux-gnueabi-")
MAKE_ARGS+=("CLANG_TRIPLE=aarch64-linux-gnu-")
MAKE_ARGS+=("AR=llvm-ar")
MAKE_ARGS+=("NM=llvm-nm")
MAKE_ARGS+=("STRIP=llvm-strip")
MAKE_ARGS+=("OBJCOPY=llvm-objcopy")
MAKE_ARGS+=("OBJDUMP=llvm-objdump")

print_success "环境配置完成"
# --- 清理工作区 ---
print_step "工作区准备"

if ! $NO_CLEAN; then
    print_info "清理构建目录..."
    if [ -d "$BUILD_DIR" ]; then
        rm -rf "$BUILD_DIR"
        print_success "构建目录已清理"
    else
        print_info "构建目录不存在，无需清理"
    fi
    mkdir -p "$BUILD_DIR"
else
    print_info "跳过清理步骤，使用现有构建目录"
fi

# --- KernelSU 设置 ---
setup_kernelsu() {
    print_step "KernelSU集成设置"
    
    if [ $KSU_ENABLE -eq 0 ]; then
        print_info "跳过 KernelSU 设置"
        KSU_ZIP_STR="NoKernelSU"
        return 0
    fi

    print_info "设置 KernelSU: $KSU_VERSION"
    
    local ksu_setup_success=false
    
    case "$KSU_VERSION" in
        "ksu")
            if [ $SuSFS_ENABLE -eq 1 ]; then
                error_exit "官方 KernelSU 不支持 SuSFS"
            fi
            KSU_ZIP_STR="KernelSU"
            print_info "安装官方KernelSU..."
            if curl -LSs "https://raw.githubusercontent.com/Prslc/KernelSU/main/kernel/setup.sh" | bash -s non-gki; then
                ksu_setup_success=true
            fi
            ;;
        "rksu")
            KSU_ZIP_STR="RKSU"
            if [ $SuSFS_ENABLE -eq 1 ]; then
                KSU_ZIP_STR="RKSU_SuSFS"
                print_info "安装RKSU with SuSFS..."
                if curl -LSs "https://raw.githubusercontent.com/rsuntk/KernelSU/main/kernel/setup.sh" | bash -s susfs-v1.5.5; then
                    ksu_setup_success=true
                fi
            else
                print_info "安装RKSU..."
                if curl -LSs "https://raw.githubusercontent.com/rsuntk/KernelSU/main/kernel/setup.sh" | bash -s main; then
                    ksu_setup_success=true
                fi
            fi
            ;;
        "sukisu")
            KSU_ZIP_STR="SukiSU"
            if [ $SuSFS_ENABLE -eq 1 ]; then
                KSU_ZIP_STR="SukiSU_SuSFS"
                print_info "安装SukiSU with SuSFS..."
                if curl -LSs "https://raw.githubusercontent.com/ShirkNeko/KernelSU/main/kernel/setup.sh" | bash -s susfs-dev; then
                    ksu_setup_success=true
                fi
            else
                print_info "安装SukiSU..."
                if curl -LSs "https://raw.githubusercontent.com/ShirkNeko/KernelSU/main/kernel/setup.sh" | bash -s dev; then
                    ksu_setup_success=true
                fi
            fi
            ;;
        "sukisu-ultra")
            KSU_ZIP_STR="SukiSU-Ultra"
            local BRANCH_NAME="nongki"
            if [ $SuSFS_ENABLE -eq 1 ]; then
                KSU_ZIP_STR="SukiSU-Ultra_SuSFS"
                BRANCH_NAME="susfs-main"
            fi
            print_info "安装SukiSU-Ultra ($BRANCH_NAME)..."
            if curl -LSs "https://raw.githubusercontent.com/SukiSU-Ultra/SukiSU-Ultra/main/kernel/setup.sh" | bash -s "$BRANCH_NAME"; then
                ksu_setup_success=true
                # 处理版本信息
                if curl -fsSL "https://raw.githubusercontent.com/SukiSU-Ultra/SukiSU-Ultra/$BRANCH_NAME/kernel/Makefile" -o "KernelSU/kernel/Makefile" 2>/dev/null; then
                    local KSU_MAKEFILE_PATH="KernelSU/kernel/Makefile"
                    if [ -f "$KSU_MAKEFILE_PATH" ]; then
                        local KSU_VERSION_API=$(grep 'KSU_VERSION_API :=' "$KSU_MAKEFILE_PATH" | awk -F':=' '{print $2}' | xargs)
                        if [ -n "$KSU_VERSION_API" ]; then
                            sed -i "s|KSU_VERSION_FULL :=.*|KSU_VERSION_FULL := v${KSU_VERSION_API}-且听风吟|" "$KSU_MAKEFILE_PATH"
                            print_info "KernelSU版本设置为: v${KSU_VERSION_API}"
                        fi
                    fi
                fi
            fi
            ;;
        *)
            error_exit "不支持的 KernelSU 类型: $KSU_VERSION"
            ;;
    esac
    
    if $ksu_setup_success; then
        print_success "KernelSU 设置完成: $KSU_ZIP_STR"
    else
        error_exit "KernelSU 设置失败"
    fi
}

# --- 配置设置函数 ---
SET_CONFIG() {
    local build_type=$1
    
    print_step "内核配置 ($build_type)"
    
    # MIUI 配置
    if [ "$build_type" == "MIUI" ]; then
        print_info "配置 MIUI 特定设置..."
        scripts/config --file "$BUILD_DIR/.config" \
            --set-str STATIC_USERMODEHELPER_PATH /system/bin/micd \
            -e PERF_CRITICAL_RT_TASK \
            -e SF_BINDER \
            -e OVERLAY_FS \
            -d DEBUG_FS \
            -e MIGT \
            -e MIGT_ENERGY_MODEL \
            -e MIHW \
            -e PACKAGE_RUNTIME_INFO \
            -e BINDER_OPT \
            -e KPERFEVENTS \
            -e MILLET \
            -e PERF_HUMANTASK \
            -d LTO_CLANG \
            -d LOCALVERSION_AUTO \
            -e SF_BINDER \
            -e XIAOMI_MIUI \
            -d MI_MEMORY_SYSFS \
            -e TASK_DELAY_ACCT \
            -e MIUI_ZRAM_MEMORY_TRACKING \
            -d CONFIG_MODULE_SIG_SHA512 \
            -d CONFIG_MODULE_SIG_HASH \
            -e MI_FRAGMENTION \
            -e PERF_HELPER \
            -e BOOTUP_RECLAIM \
            -e MI_RECLAIM \
            -e RTMM
    fi

    # KernelSU 配置
    if [ "$KSU_VERSION" == "sukisu-ultra" ]; then
        scripts/config --file "$BUILD_DIR/.config" -e KSU_MANUAL_HOOK
    else
        scripts/config --file "$BUILD_DIR/.config" -d KSU_MANUAL_HOOK
    fi

    # KPM 配置
    if [ $KPM_ENABLE -eq 1 ]; then
        print_info "启用 KPM 支持..."
        scripts/config --file "$BUILD_DIR/.config" \
            -e KPM \
            -e KALLSYMS \
            -e KALLSYMS_ALL
    else
        scripts/config --file "$BUILD_DIR/.config" \
            -d KPM \
            -d KALLSYMS \
            -d KALLSYMS_ALL
    fi

    # SuSFS 配置
    if [ $SuSFS_ENABLE -eq 1 ]; then
        print_info "启用 SuSFS 支持..."
        scripts/config --file "$BUILD_DIR/.config" \
            -e KSU \
            -e KSU_SUSFS \
            -d KSU_MANUAL_HOOK \
            -e KSU_SUSFS_HAS_MAGIC_MOUNT \
            -e KSU_SUSFS_SUS_PATH \
            -e KSU_SUSFS_SUS_MOUNT \
            -e KSU_SUSFS_AUTO_ADD_SUS_KSU_DEFAULT_MOUNT \
            -e KSU_SUSFS_AUTO_ADD_SUS_BIND_MOUNT \
            -e KSU_SUSFS_SUS_KSTAT \
            -e KSU_SUSFS_TRY_UMOUNT \
            -e KSU_SUSFS_AUTO_ADD_TRY_UMOUNT_FOR_BIND_MOUNT \
            -e KSU_SUSFS_SPOOF_UNAME \
            -e KSU_SUSFS_ENABLE_LOG \
            -e KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS \
            -e KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG \
            -e KSU_MULTI_MANAGER_SUPPORT \
            -e KSU_SUSFS_OPEN_REDIRECT \
            -e KSU_SUSFS_SUS_MAP \
            -e KSU_SUSFS_SUS_SU \
            -d KSU_SUSFS_ADD_SUS_MAP
    else
        scripts/config --file "$BUILD_DIR/.config" \
            -d KSU \
            -d KSU_SUSFS \
            -d KSU_MANUAL_HOOK \
            -d KSU_SUSFS_HAS_MAGIC_MOUNT \
            -d KSU_SUSFS_SUS_PATH \
            -d KSU_SUSFS_SUS_MOUNT \
            -d KSU_SUSFS_AUTO_ADD_SUS_KSU_DEFAULT_MOUNT \
            -d KSU_SUSFS_AUTO_ADD_SUS_BIND_MOUNT \
            -d KSU_SUSFS_SUS_KSTAT \
            -d KSU_SUSFS_TRY_UMOUNT \
            -d KSU_SUSFS_AUTO_ADD_TRY_UMOUNT_FOR_BIND_MOUNT \
            -d KSU_SUSFS_SPOOF_UNAME \
            -d KSU_SUSFS_ENABLE_LOG \
            -d KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS \
            -d KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG \
            -d KSU_SUSFS_OPEN_REDIRECT \
            -d KSU_MULTI_MANAGER_SUPPORT \
            -d KSU_SUSFS_SUS_MAP \
            -d KSU_SUSFS_ADD_SUS_MAP \
            -d KSU_SUSFS_SUS_SU
    fi
    
    print_success "内核配置完成"
}

# --- MIUI 设备树修改 ---
modify_miui_dts() {
    local dts_source="arch/arm64/boot/dts/vendor/qcom"
    
    print_step "MIUI设备树修改"
    
    # 备份dts
    if [ -d "$dts_source" ]; then
        print_info "备份设备树文件..."
        cp -a "${dts_source}" .dts.bak
    else
        print_warning "设备树源目录不存在: $dts_source"
        return 0
    fi

    print_info "应用 MIUI 设备树修改..."

    # 面板尺寸修正
    color_echo "$yellow" "修正面板尺寸..."
    sed -i 's/<154>/<1537>/g' ${dts_source}/dsi-panel-j1s*
    sed -i 's/<154>/<1537>/g' ${dts_source}/dsi-panel-j2*
    sed -i 's/<155>/<1544>/g' ${dts_source}/dsi-panel-j3s-37-02-0a-dsc-video.dtsi
    sed -i 's/<155>/<1545>/g' ${dts_source}/dsi-panel-j11-38-08-0a-fhd-cmd.dtsi
    sed -i 's/<155>/<1546>/g' ${dts_source}/dsi-panel-k11a-38-08-0a-dsc-cmd.dtsi
    sed -i 's/<155>/<1546>/g' ${dts_source}/dsi-panel-l11r-38-08-0a-dsc-cmd.dtsi
    sed -i 's/<70>/<695>/g' ${dts_source}/dsi-panel-j11-38-08-0a-fhd-cmd.dtsi
    sed -i 's/<70>/<695>/g' ${dts_source}/dsi-panel-j3s-37-02-0a-dsc-video.dtsi
    sed -i 's/<70>/<695>/g' ${dts_source}/dsi-panel-k11a-38-08-0a-dsc-cmd.dtsi
    sed -i 's/<70>/<695>/g' ${dts_source}/dsi-panel-l11r-38-08-0a-dsc-cmd.dtsi
    sed -i 's/<71>/<710>/g' ${dts_source}/dsi-panel-j1s*
    sed -i 's/<71>/<710>/g' ${dts_source}/dsi-panel-j2*

    # 启用智能FPS
    color_echo "$yellow" "启用智能FPS功能..."
    sed -i 's/\/\/ mi,mdss-dsi-pan-enable-smart-fps/mi,mdss-dsi-pan-enable-smart-fps/g' ${dts_source}/dsi-panel*
    sed -i 's/\/\/ mi,mdss-dsi-smart-fps-max_framerate/mi,mdss-dsi-smart-fps-max_framerate/g' ${dts_source}/dsi-panel*
    sed -i 's/\/\/ qcom,mdss-dsi-pan-enable-smart-fps/qcom,mdss-dsi-pan-enable-smart-fps/g' ${dts_source}/dsi-panel*
    sed -i 's/qcom,mdss-dsi-qsync-min-refresh-rate/\/\/qcom,mdss-dsi-qsync-min-refresh-rate/g' ${dts_source}/dsi-panel*

    # 刷新率支持
    color_echo "$yellow" "配置刷新率支持..."
    sed -i 's/120 90 60/120 90 60 50 30/g' ${dts_source}/dsi-panel-g7a-36-02-0c-dsc-video.dtsi
    sed -i 's/120 90 60/120 90 60 50 30/g' ${dts_source}/dsi-panel-g7a-37-02-0a-dsc-video.dtsi
    sed -i 's/120 90 60/120 90 60 50 30/g' ${dts_source}/dsi-panel-g7a-37-02-0b-dsc-video.dtsi
    sed -i 's/144 120 90 60/144 120 90 60 50 48 30/g' ${dts_source}/dsi-panel-j3s-37-02-0a-dsc-video.dtsi

    # 亮度控制
    color_echo "$yellow" "配置亮度控制..."
    sed -i 's/\/\/39 00 00 00 00 00 03 51 03 FF/39 00 00 00 00 00 03 51 03 FF/g' ${dts_source}/dsi-panel-j9-38-0a-0a-fhd-video.dtsi
    sed -i 's/\/\/39 00 00 00 00 00 03 51 0D FF/39 00 00 00 00 00 03 51 0D FF/g' ${dts_source}/dsi-panel-j2-p2-1-38-0c-0a-dsc-cmd.dtsi
    sed -i 's/\/\/39 00 00 00 00 00 05 51 0F 8F 00 00/39 00 00 00 00 00 05 51 0F 8F 00 00/g' ${dts_source}/dsi-panel-j1s-42-02-0a-dsc-cmd.dtsi
    sed -i 's/\/\/39 00 00 00 00 00 05 51 0F 8F 00 00/39 00 00 00 00 00 05 51 0F 8F 00 00/g' ${dts_source}/dsi-panel-j1s-42-02-0a-mp-dsc-cmd.dtsi
    sed -i 's/\/\/39 00 00 00 00 00 05 51 0F 8F 00 00/39 00 00 00 00 00 05 51 0F 8F 00 00/g' ${dts_source}/dsi-panel-j2-mp-42-02-0b-dsc-cmd.dtsi
    sed -i 's/\/\/39 00 00 00 00 00 05 51 0F 8F 00 00/39 00 00 00 00 00 05 51 0F 8F 00 00/g' ${dts_source}/dsi-panel-j2-p2-1-42-02-0b-dsc-cmd.dtsi
    sed -i 's/\/\/39 00 00 00 00 00 05 51 0F 8F 00 00/39 00 00 00 00 00 05 51 0F 8F 00 00/g' ${dts_source}/dsi-panel-j2s-mp-42-02-0a-dsc-cmd.dtsi
    sed -i 's/\/\/39 01 00 00 00 00 03 51 00 00/39 01 00 00 00 00 03 51 00 00/g' ${dts_source}/dsi-panel-j2-38-0c-0a-dsc-cmd.dtsi
    sed -i 's/\/\/39 01 00 00 00 00 03 51 00 00/39 01 00 00 00 00 03 51 00 00/g' ${dts_source}/dsi-panel-j2-38-0c-0a-dsc-cmd.dtsi
    sed -i 's/\/\/39 01 00 00 00 00 03 51 03 FF/39 01 00 00 00 00 03 51 03 FF/g' ${dts_source}/dsi-panel-j11-38-08-0a-fhd-cmd.dtsi
    sed -i 's/\/\/39 01 00 00 00 00 03 51 03 FF/39 01 00 00 00 00 03 51 03 FF/g' ${dts_source}/dsi-panel-j9-38-0a-0a-fhd-video.dtsi
    sed -i 's/\/\/39 01 00 00 00 00 03 51 07 FF/39 01 00 00 00 00 03 51 07 FF/g' ${dts_source}/dsi-panel-j1u-42-02-0b-dsc-cmd.dtsi
    sed -i 's/\/\/39 01 00 00 00 00 03 51 07 FF/39 01 00 00 00 00 03 51 07 FF/g' ${dts_source}/dsi-panel-j2-42-02-0b-dsc-cmd.dtsi
    sed -i 's/\/\/39 01 00 00 00 00 03 51 07 FF/39 01 00 00 00 00 03 51 07 FF/g' ${dts_source}/dsi-panel-j2-p1-42-02-0b-dsc-cmd.dtsi
    sed -i 's/\/\/39 01 00 00 00 00 03 51 0F FF/39 01 00 00 00 00 03 51 0F FF/g' ${dts_source}/dsi-panel-j1u-42-02-0b-dsc-cmd.dtsi
    sed -i 's/\/\/39 01 00 00 00 00 03 51 0F FF/39 01 00 00 00 00 03 51 0F FF/g' ${dts_source}/dsi-panel-j2-42-02-0b-dsc-cmd.dtsi
    sed -i 's/\/\/39 01 00 00 00 00 03 51 0F FF/39 01 00 00 00 00 03 51 0F FF/g' ${dts_source}/dsi-panel-j2-p1-42-02-0b-dsc-cmd.dtsi
    sed -i 's/\/\/39 01 00 00 00 00 05 51 07 FF 00 00/39 01 00 00 00 00 05 51 07 FF 00 00/g' ${dts_source}/dsi-panel-j1s-42-02-0a-dsc-cmd.dtsi
    sed -i 's/\/\/39 01 00 00 00 00 05 51 07 FF 00 00/39 01 00 00 00 00 05 51 07 FF 00 00/g' ${dts_source}/dsi-panel-j1s-42-02-0a-mp-dsc-cmd.dtsi
    sed -i 's/\/\/39 01 00 00 00 00 05 51 07 FF 00 00/39 01 00 00 00 00 05 51 07 FF 00 00/g' ${dts_source}/dsi-panel-j2-mp-42-02-0b-dsc-cmd.dtsi
    sed -i 's/\/\/39 01 00 00 00 00 05 51 07 FF 00 00/39 01 00 00 00 00 05 51 07 FF 00 00/g' ${dts_source}/dsi-panel-j2-p2-1-42-02-0b-dsc-cmd.dtsi
    sed -i 's/\/\/39 01 00 00 00 00 05 51 07 FF 00 00/39 01 00 00 00 00 05 51 07 FF 00 00/g' ${dts_source}/dsi-panel-j2s-mp-42-02-0a-dsc-cmd.dtsi
    sed -i 's/\/\/39 01 00 00 01 00 03 51 03 FF/39 01 00 00 01 00 03 51 03 FF/g' ${dts_source}/dsi-panel-j11-38-08-0a-fhd-cmd.dtsi
    sed -i 's/\/\/39 01 00 00 11 00 03 51 03 FF/39 01 00 00 11 00 03 51 03 FF/g' ${dts_source}/dsi-panel-j2-p2-1-38-0c-0a-dsc-cmd.dtsi

    color_echo "$green" "MIUI 设备树修改完成"
}


# --- AOSP 构建函数 ---
Build_AOSP() {
    print_step "开始构建 AOSP 内核"
    
    # 配置内核
    print_info "配置 ${TARGET_DEVICE}_defconfig..."
    if ! safe_make "${TARGET_DEVICE}_defconfig"; then
        error_exit "AOSP配置失败"
    fi
    
    # 应用配置
    SET_CONFIG "AOSP"
    
    # 设置版本信息
    echo 1 > "$BUILD_DIR/.version"
    export KBUILD_BUILD_VERSION="1" 
    export LOCALVERSION="-g92c089fc2d37"
    export KBUILD_BUILD_USER="Chinese" 
    export KBUILD_BUILD_HOST="root" 
    export KBUILD_BUILD_TIMESTAMP="Wed Jun 5 13:27:08 UTC 2024"
    
    # 开始编译
    local start_time=$(date +%s)
    print_info "开始编译AOSP内核..."
    
    if ! safe_make; then
        error_exit "AOSP内核编译失败"
    fi
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    # 打包镜像
    Image_Repack "AOSP"
    
    print_success "AOSP 构建完成，耗时: $((duration / 60))分$((duration % 60))秒"
}

# --- MIUI 构建函数 ---
Build_MIUI() {
    print_step "开始构建 MIUI 内核"
    
    # 清理并重新配置
    if ! $NO_CLEAN; then
        print_info "清理构建目录..."
        rm -rf "$BUILD_DIR"
        mkdir -p "$BUILD_DIR"
    else
        print_info "跳过清理，使用现有构建目录"
    fi
    
    # 修改MIUI设备树
    modify_miui_dts
    
    # 配置内核
    print_info "配置 ${TARGET_DEVICE}_defconfig..."
    if ! safe_make "${TARGET_DEVICE}_defconfig"; then
        error_exit "MIUI配置失败"
    fi
    
    # 应用MIUI特定配置
    SET_CONFIG "MIUI"
    
    # 设置版本信息
    echo 1 > "$BUILD_DIR/.version"
    export KBUILD_BUILD_VERSION="1"
    export LOCALVERSION="-g92c089fc2d37" 
    export KBUILD_BUILD_USER="Chinese"
    export KBUILD_BUILD_HOST="root"
    export KBUILD_BUILD_TIMESTAMP="Wed Jun 5 13:27:08 UTC 2024"
    
    # 开始编译
    local start_time=$(date +%s)
    print_info "开始编译MIUI内核..."
    
    if ! safe_make; then
        error_exit "MIUI内核编译失败"
    fi
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    # 打包镜像
    Image_Repack "MIUI"
    
    # 恢复设备树
    if [ -d ".dts.bak" ]; then
        print_info "恢复原始设备树文件..."
        rm -rf "arch/arm64/boot/dts/vendor/qcom"
        mv .dts.bak "arch/arm64/boot/dts/vendor/qcom"
        print_success "设备树恢复完成"
    fi
    
    print_success "MIUI 构建完成，耗时: $((duration / 60))分$((duration % 60))秒"
}

# --- KPM 补丁函数 ---
Patch_KPM() {
    if [ $KPM_ENABLE -ne 1 ] || [ "$KSU_VERSION" != "sukisu-ultra" ]; then
        return 0
    fi
    
    print_step "应用 KPM 补丁"
    
    local image_dir="$BUILD_DIR/arch/arm64/boot"
    cd "$image_dir"
    
    # 下载并应用补丁
    if curl -LSs "https://github.com/SukiSU-Ultra/SukiSU_KernelPatch_patch/releases/download/0.12.2/patch_linux" -o patch; then
        chmod +x patch
        if ./patch; then
            rm -f Image
            mv oImage Image
            print_success "KPM 补丁应用成功"
        else
            print_warning "KPM 补丁应用失败，使用原始镜像"
        fi
        rm -f patch
    else
        print_warning "无法下载 KPM 补丁，使用原始镜像"
    fi
    
    cd "$SCRIPT_DIR"
}

# --- 镜像打包函数 ---
Image_Repack() {
    local system_type=$1
    local KERNEL_SRC="$SCRIPT_DIR"
    
    print_step "打包 $system_type 镜像"
    
    # 检查内核镜像
    local image_path="$BUILD_DIR/arch/arm64/boot/Image"
    if [ ! -f "$image_path" ]; then
        error_exit "未找到内核镜像 [$image_path]"
    fi
    print_success "找到内核镜像: $image_path"

    # KPM 补丁
    Patch_KPM

    # 生成DTB
    local dtb_path="$BUILD_DIR/arch/arm64/boot/dtb"
    print_info "生成DTB文件: $dtb_path"
    find "$BUILD_DIR/arch/arm64/boot/dts" -name '*.dtb' -exec cat {} + > "$dtb_path" 2>/dev/null || {
        print_warning "未找到DTB文件，创建空文件"
        touch "$dtb_path"
    }

    # 准备AnyKernel3
    if [ ! -d "anykernel" ]; then
        print_info "下载 AnyKernel3..."
        if git clone https://github.com/liyafe1997/AnyKernel3 -b kona --single-branch --depth=1 anykernel; then
            print_success "AnyKernel3 下载成功"
        else
            error_exit "AnyKernel3 下载失败"
        fi
    else
        print_info "使用现有的 AnyKernel3 目录"
    fi

    # 清理并准备内核文件
    rm -rf anykernel/kernels/
    mkdir -p anykernel/kernels/

    cp "$image_path" anykernel/kernels/
    cp "$dtb_path" anykernel/kernels/

    # 创建刷机包文件名
    local timestamp=$(date +'%Y%m%d_%H%M%S')
    local ZIP_FILENAME
    if [ "$system_type" == "MIUI" ]; then
        ZIP_FILENAME="Kernel_MIUI_${TARGET_DEVICE}_${KSU_ZIP_STR}_${timestamp}_anykernel3_${GIT_COMMIT_ID}.zip"
    else
        ZIP_FILENAME="Kernel_AOSP_${TARGET_DEVICE}_${KSU_ZIP_STR}_${timestamp}_anykernel3_${GIT_COMMIT_ID}.zip"
    fi

    # 创建刷机包
    print_info "创建刷机包: $ZIP_FILENAME"
    cd anykernel
    if zip -r9 "$ZIP_FILENAME" ./* -x .git .gitignore out/ ./*.zip 2>/dev/null; then
        mv "$ZIP_FILENAME" ../
        print_success "刷机包创建成功: $ZIP_FILENAME"
    else
        error_exit "刷机包创建失败"
    fi
    cd ..

    print_success "$system_type 镜像打包完成"
}

# --- 主执行流程 ---
main() {
    print_step "开始内核构建流程"
    
    local start_time=$(date +%s)
    local build_success=true
    
    # 设置 KernelSU
    setup_kernelsu
    
    # 根据目标系统进行构建
    case "$TARGET_SYSTEM" in
        "aosp")
            if ! Build_AOSP; then
                build_success=false
            fi
            ;;
        "miui")
            if ! Build_MIUI; then
                build_success=false
            fi
            ;;
        "all")
            if ! Build_AOSP; then
                build_success=false
            fi
            if ! Build_MIUI; then
                build_success=false
            fi
            ;;
        *)
            error_exit "未知的目标系统: $TARGET_SYSTEM"
            ;;
    esac
    
    local end_time=$(date +%s)
    local total_duration=$((end_time - start_time))
    local total_minutes=$((total_duration / 60))
    local total_seconds=$((total_duration % 60))
    
    print_step "构建完成"
    if $build_success; then
        print_success "内核构建全部完成!"
        print_success "总耗时: ${total_minutes}分${total_seconds}秒"
        
        # 显示生成的刷机包
        print_info "生成的刷机包:"
        ls -la *.zip 2>/dev/null || print_warning "未找到刷机包文件"
    else
        error_exit "构建过程中出现错误"
    fi
}

# 执行主函数
main "$@"
