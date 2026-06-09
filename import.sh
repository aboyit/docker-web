#!/bin/sh

set -u

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
env_file="${script_dir}/.env"
log_dir="${script_dir}/logs"

mkdir -p "${log_dir}"

if [ ! -f "${env_file}" ]; then
    echo ".env khong ton tai tai: ${env_file}"
    exit 1
fi

if ! command -v docker >/dev/null 2>&1; then
    echo "Khong tim thay lenh docker"
    exit 1
fi

set -a
. "${env_file}"
set +a

trim_cr() {
    printf '%s' "$1" | tr -d '\r'
}

MYSQL_ROOT_PASSWORD=$(trim_cr "${MYSQL_ROOT_PASSWORD:-}")

if [ -z "${MYSQL_ROOT_PASSWORD}" ]; then
    echo "MYSQL_ROOT_PASSWORD dang rong trong .env"
    exit 1
fi

run_query() {
    docker compose exec -T mariadb mariadb -N -B -u root "-p${MYSQL_ROOT_PASSWORD}" -e "$1"
}

database_exists() {
    database_name="$1"
    exists=$(run_query "SHOW DATABASES LIKE '${database_name}';" 2>/dev/null)

    if [ "${exists}" = "${database_name}" ]; then
        return 0
    fi

    return 1
}

create_database() {
    database_name="$1"
    run_query "CREATE DATABASE \`${database_name}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
}

choose_database() {
    db_tmp=$(mktemp)
    run_query "SHOW DATABASES;" | grep -Ev '^(information_schema|performance_schema|mysql|sys)$' > "${db_tmp}"

    if [ -s "${db_tmp}" ]; then
        echo "Chon database can import:"
        nl -ba "${db_tmp}"
        echo "M. Nhap ten database thu cong"
        printf "Lua chon: "
        IFS= read -r choice

        case "${choice}" in
            ''|*[!0-9]*) ;;
            *)
                selected_db=$(sed -n "${choice}p" "${db_tmp}")
                if [ -n "${selected_db}" ]; then
                    rm -f "${db_tmp}"
                    return 0
                fi
                ;;
        esac
    fi

    rm -f "${db_tmp}"

    printf "Nhap ten database can import: "
    IFS= read -r manual_name

    if [ -z "${manual_name}" ]; then
        echo "Ten database khong duoc de trong"
        exit 1
    fi

    case "${manual_name}" in
        *[!A-Za-z0-9_]* )
            echo "Ten database chi duoc gom chu cai, so va dau gach duoi"
            exit 1
            ;;
    esac

    if ! database_exists "${manual_name}"; then
        printf "Database %s chua ton tai. Tao moi? [y/N]: " "${manual_name}"
        IFS= read -r choice
        case "${choice}" in
            y|Y)
                if ! create_database "${manual_name}" >/dev/null 2>&1; then
                    echo "Khong the tao database ${manual_name}"
                    exit 1
                fi
                ;;
            *)
                echo "Da huy import"
                exit 1
                ;;
        esac
    fi

    selected_db="${manual_name}"
}

choose_import_file() {
    preset_file="${1:-}"

    if [ -n "${preset_file}" ]; then
        if [ ! -f "${preset_file}" ]; then
            echo "Khong tim thay file ${preset_file}"
            exit 1
        fi

        selected_file="${preset_file}"
        return 0
    fi

    file_tmp=$(mktemp)
    find "${script_dir}" -maxdepth 4 -type f \( -name "*.sql" -o -name "*.sql.gz" \) | sort > "${file_tmp}"

    if [ -s "${file_tmp}" ]; then
        echo "Chon file import:"
        nl -ba "${file_tmp}"
        echo "M. Nhap duong dan file thu cong"
        printf "Lua chon: "
        IFS= read -r choice

        case "${choice}" in
            ''|*[!0-9]*) ;;
            *)
                selected_file=$(sed -n "${choice}p" "${file_tmp}")
                if [ -n "${selected_file}" ]; then
                    rm -f "${file_tmp}"
                    return 0
                fi
                ;;
        esac
    fi

    rm -f "${file_tmp}"

    printf "Nhap duong dan file .sql hoac .sql.gz: "
    IFS= read -r manual_file

    if [ -z "${manual_file}" ] || [ ! -f "${manual_file}" ]; then
        echo "Khong tim thay file ${manual_file}"
        exit 1
    fi

    selected_file="${manual_file}"
}

import_database() {
    import_file="$1"
    database_name="$2"
    timestamp=$(date +%Y%m%d_%H%M%S)
    log_file="${log_dir}/import_${database_name}_${timestamp}.log"

    echo "Bat dau import '${import_file}' vao database '${database_name}'"
    echo "Log: ${log_file}"

    case "${import_file}" in
        *.sql.gz)
            gzip -dc "${import_file}" | docker compose exec -T mariadb mariadb -u root "-p${MYSQL_ROOT_PASSWORD}" "${database_name}" >"${log_file}" 2>&1
            status=$?
            ;;
        *)
            docker compose exec -T mariadb mariadb -u root "-p${MYSQL_ROOT_PASSWORD}" "${database_name}" < "${import_file}" >"${log_file}" 2>&1
            status=$?
            ;;
    esac

    if [ "${status}" -ne 0 ]; then
        echo "Import that bai. Xem log tai: ${log_file}"
        exit "${status}"
    fi

    echo "Import thanh cong vao database '${database_name}'"
    echo "Log: ${log_file}"
}

choose_database
choose_import_file "${1:-}"
import_database "${selected_file}" "${selected_db}"
