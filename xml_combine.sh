#!/bin/bash

# Script - Combine XML (Also works with CSVs that have no header)
# $1 - File mask of files to be combined. Ex: "CFNC XML*"
# $2 - Working Directory (Not Required)
# $3 - New Root (XML Only, Not Required)

#### Function - check_error
####     If receives a status different than zero, displays error message and exists. 
####     Otherwise, just displays the message.
#### $1 - Status Code
#### $2 - Error or Info Message
check_error() {
    local status_code="${1}"
    local message="${2}"

    if [ "${status_code}" -ne 0 ]; then
        echo "${0} - Error: ${message}" >&2
        popd &> /dev/null
        kill $$ & 
        exit 1 
    else
        echo "${0} - ${message}" >&2
    fi
}

#### Function - unzip_files
####    Unzips zip files to directory of same name.
####    Returns - List of directories created
#### $1 - File mask 
unzip_files() {
    local zip_dir=
    find -type f -iname "${file_mask}.zip" | while read zipfile; do
        local zip_dir="${zipfile%.zip}"
        unzip -o -d "${zip_dir}" "${zipfile}" &> /dev/null
        check_error "$?" "Extracting zip file ${zipfile}."
        # We have to use echo to return arrays, as you can't "return" anything in
        # bash except for integer values. 
        echo "${zip_dir}"
        rm "${zipfile}" &> /dev/null
        check_error "$?" "Removing zip file ${zipfile}."
    done
}

#### Function - create_new_file
####    If working with XML files, call this function to create a file with the new root, so 
####    that other files can be appended to it.
####    Returns - Child tag to encapsulate other XML fragments 
#### $1 - New File Name
#### $2 - New Root. Ex: HighSchoolTranscripts
#### $3 - Source file to parse
create_new_file() {
    local new_file="${1}"
    local new_root="${2}"
    local source_file="${3}" 

    local old_root=
    local old_child=
    local xml_tag=
    local first_line="$(head -n1 "${source_file}")"

    # Expecting the first two lines to be encoding and spec, if it's got a root definied
    old_root="$(grep -v "<?xml" "${source_file}" | \
        sed -nr 's/^<([A-Za-z0-9]+?)\s?>?.*$/\1/p' | \
        while read xml_tag; do echo "${xml_tag}"; break; done)"
    grep -v "<?xml" "${source_file}" | head -n2 | \
        sed "s/${old_root}/${new_root}/" | \
        sed -nr "s/^(<${new_root}[^<]*?>)(.*)$/\1\n\2/p" > "${new_file}"
    check_error "$?" "Setting output header."

    old_child="$(grep -v "<?xml" "${new_file}" | tail -n1)"
    if [ "${first_line:0:5}" = "<?xml" ]; then
        echo -e "${first_line}\n$(head -n1 "${new_file}")" > "${new_file}"
    else 
        echo "$(head -n1 "${new_file}")" > "${new_file}"
    fi

    echo "${old_child}"
}

#### Function - split_xml 
####    Splits XML files into a list of new files, one level deeper.
####    Returns - List of split files (excluding XML header)
#### $1 - Source file, i.e. the file to break up
#### $2 - File Mask (Also used for searching)
split_xml() {
    local source_file="${1}"
    local file_mask="${2}"

    local filename_regex="^(./)?${source_file%.*}-([0-9][0-9]?[0-9]?[1-9]|[1-9][0-9]?[0-9]?[0-9])\.${source_file##*.}"

    xml_split "${source_file}" &> /dev/null
    check_error "$?" "Splitting XML file, ${source_file}."
    
    find . -iname "${file_mask}*.${source_file##*.}" | while read filename; do
        [[ $filename =~ $filename_regex && -n $filename ]] && echo "${filename}"
    done
} 

#### Function - get_file_list 
####    Gets a list of files to be combined into a single file. If "Loop Only Once" is
####    specified, then only the output filename is returned.
####    Returns - File List
#### $1 - File mask. Ex: "CFNC XML*"
#### $2 - Loop only once, and return new_file name? Ex: y 
get_file_list() {
    local file_mask="${1}"
    local loop_once="${2}"
    local new_file=

    find . \( -iname "${file_mask}" -type f -not -iname "*combined*" -not -iname "*.cmb" \) | while read filename; do
        if [[ -n ${loop_once} && ${loop_once,,} = y ]]; then
            new_file="$(basename "${filename}")"
            new_file="${file_mask%\**}-combined_$(date +"%y%m%d%m%H%M").${new_file##*.}"
            echo "${new_file}"
            break
        else
            echo "${filename}" 
        fi
    done
}

#### MAIN SCRIPT ####
file_mask="${1}"
work_dir="${2}"
new_root="${3}" 

# Debug Only
echo "$(pwd) $(whoami)"

[ -n "${work_dir}" ] && pushd "${work_dir}" >> /dev/null

dirs_to_clean="$(unzip_files "${file_mask}")"
new_file="$(get_file_list "${file_mask}" "y")"
source_files="$(get_file_list "${file_mask}" "n")"
sample_file="$(echo "${source_files}" | while read first_file; do echo "${first_file}"; break; done)"

old_child=
xml_fragments=
xml_header=

if [ -n "${new_root}" ]; then # Shouldn't have been doing assignment in subshell
    old_child="$(create_new_file "${new_file}" "${new_root}" "${sample_file}")"
fi
    
echo "${source_files}" | while read source_file; do
    if [ -n "${source_file}" ]; then
        if [ -n "${new_root}" ]; then
            xml_fragments="$(split_xml "${source_file}" "${file_mask}")"
            echo "${xml_fragments}" | while read xml_fragment; do
                #echo -n "${old_child}" >> "${new_file}"
                cat "${xml_fragment}" | grep -v "<?xml" >> "${new_file}"
                check_error "$?" "Adding fragment ${xml_fragment}."
                rm "${xml_fragment}" &> /dev/null
                check_error "$?" "Removing XML fragment ${xml_fragment}."
            done
            xml_header="${source_file%.*}-00.${source_file##*.}"
            rm "$xml_header" &> /dev/null
            check_error "$?" "Removing XML Header ${xml_header}."
        else
                cat "${source_file}" >> "${new_file}"
                check_error "$?" "Adding source file ${source_file}."
        fi    
        rm "${source_file}" &> /dev/null
        check_error "${?}" "Removing source file ${source_file}."
    fi
done

echo "${dirs_to_clean}" | while read empty_dir; do
    if [ -n "${empty_dir}" ]; then
        rmdir "${empty_dir}" &> /dev/null
        check_error "${?}" "Removing directory ${empty_dir}."
    fi
done

if [ -n "${new_root}" ]; then
    echo "Applying closing tag, ${new_root}  for root gilr, ${new_file}."
    echo "</${new_root/</</}>" >> "${new_file}"
fi
    
[ -n "${work_dir}" ] && popd > /dev/null

check_error 0 "Reassembly completed in ${new_file}"

exit 0
