#!/bin/sh

set -u

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
env_file="${script_dir}/.env"
log_dir="${script_dir}/logs"
backup_dir="${script_dir}/backups"

mkdir -p "${log_dir}" "${backup_dir}"

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

get_databases() {
    docker compose exec -T mariadb mariadb -N -B -u root "-p${MYSQL_ROOT_PASSWORD}" -e "SHOW DATABASES;" 2>/dev/null | grep -Ev '^(information_schema|performance_schema|mysql|sys)$'
}

choose_database() {
    db_tmp=$(mktemp)
    get_databases > "${db_tmp}"

    if [ ! -s "${db_tmp}" ]; then
        rm -f "${db_tmp}"
        echo "Khong co database nao de export"
        exit 1
    fi

    echo "Chon database can export:"
    nl -ba "${db_tmp}"
    printf "Lua chon: "
    IFS= read -r choice

    case "${choice}" in
        ''|*[!0-9]*)
            rm -f "${db_tmp}"
            echo "Lua chon khong hop le"
            exit 1
            ;;
    esac

    selected_db=$(sed -n "${choice}p" "${db_tmp}")
    rm -f "${db_tmp}"

    if [ -z "${selected_db}" ]; then
        echo "Lua chon khong hop le"
        exit 1
    fi
}

choose_output_file() {
    timestamp=$(date +%Y%m%d_%H%M%S)
    default_file="${backup_dir}/${selected_db}_${timestamp}.sql"

    printf "Nhap file output [%s]: " "${default_file}"
    IFS= read -r manual_file

    if [ -z "${manual_file}" ]; then
        selected_output="${default_file}"
    else
        selected_output="${manual_file}"
    fi

    mkdir -p "$(dirname "${selected_output}")"
}

export_database() {
    database_name="$1"
    output_file="$2"
    timestamp=$(date +%Y%m%d_%H%M%S)
    log_file="${log_dir}/export_${database_name}_${timestamp}.log"

    echo "Bat dau export database '${database_name}'"
    echo "File export: ${output_file}"
    echo "Log: ${log_file}"

    case "${output_file}" in
        *.gz)
            docker compose exec -T mariadb mariadb-dump -u root "-p${MYSQL_ROOT_PASSWORD}" --default-character-set=utf8mb4 --single-transaction --quick --routines --triggers --events "${database_name}" 2>"${log_file}" | gzip > "${output_file}"
            status=$?
            ;;
        *)
            docker compose exec -T mariadb mariadb-dump -u root "-p${MYSQL_ROOT_PASSWORD}" --default-character-set=utf8mb4 --single-transaction --quick --routines --triggers --events "${database_name}" > "${output_file}" 2>"${log_file}"
            status=$?
            ;;
    esac

    if [ "${status}" -ne 0 ]; then
        rm -f "${output_file}"
        echo "Export that bai. Xem log tai: ${log_file}"
        exit "${status}"
    fi

    echo "Export thanh cong: ${output_file}"
    echo "Log: ${log_file}"
}

choose_database
choose_output_file
export_database "${selected_db}" "${selected_output}"
