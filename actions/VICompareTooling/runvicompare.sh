#!/bin/bash
# Reads changed files from /workspace/changed-files.txt and generates HTML
# reports for any file whose content is identified as a LabVIEW VI or LVCC
# file by inspecting bytes 9-12 for the magic string LVIN or LVCC.
# Each line of changed-files.txt is a tab-separated pair:
#   <STATUS>\t<path/to/file>
# where STATUS is A (added), D (deleted), or M (modified).
#
# Modified VIs  → CreateComparisonReport  (base vs head),  diff-report-*.html
# Added VIs     → PrintToSingleFileHtml   (head version),  print-report-*.html
# Deleted VIs   → PrintToSingleFileHtml   (base version),  print-report-*.html

CHANGED_FILES_FILE='/workspace/changed-files.txt'
REPORT_DIR='/workspace/vi-compare-reports'
LABVIEW_PATH='/usr/local/natinst/LabVIEW-2026-64/labviewprofull'
ADDITIONAL_OP_DIR='/workspace/VICompareTooling'

mkdir -p "$REPORT_DIR"
mkdir -p "/tmp/natinst"
echo "1" > /tmp/natinst/LVContainer.txt

# Returns 0 (true) if the file at the given path is a LabVIEW VI or LVCC file,
# identified by the magic bytes at offset 8 (bytes 9-12): LVIN or LVCC.
is_vi_file() {
  local path="$1"
  local magic
  [ -f "$path" ] || return 1
  magic=$(dd if="$path" bs=1 skip=8 count=4 2>/dev/null)
  [[ "$magic" == "LVIN" || "$magic" == "LVCC" ]]
}

if [ ! -f "$CHANGED_FILES_FILE" ]; then
  echo "No changed-files.txt found. Exiting."
  exit 0
fi

FAILED=0

# Set IFS to tab for the read loop, saving and restoring the original value.
ORIG_IFS="$IFS"
IFS=$'\t'
while read -r status file; do
  IFS="$ORIG_IFS"
  file="$(echo "$file" | tr -d '\r')"
  status="$(echo "$status" | tr -d '\r')"
  IFS=$'\t'
  [[ -z "$file" ]] && continue

  BASE_NAME="$(basename "$file")"

  if [[ "$status" == "M" ]]; then
    # ---------- Modified: compare base vs head ----------
    VI_BASE="/workspace/vi-base/$file"
    VI_HEAD="/workspace/$file"
    REPORT_PATH="$REPORT_DIR/diff-report-$BASE_NAME.html"

    if [ ! -f "$VI_HEAD" ]; then
      echo "Warning: Head version not found: $VI_HEAD, skipping."
      continue
    fi
    if [ ! -f "$VI_BASE" ]; then
      echo "Warning: Base version not found: $VI_BASE, skipping."
      continue
    fi
    if ! is_vi_file "$VI_HEAD"; then
      echo "Skipping $file: not a LabVIEW VI file."
      continue
    fi
    if ! is_vi_file "$VI_BASE"; then
      echo "Skipping $file: base version is not a LabVIEW VI file."
      continue
    fi

    echo "Running LabVIEWCLI CreateComparisonReport for modified VI: $file"

    # -o overwrites an existing report file; -c continues if LabVIEW is already open.
    LabVIEWCLI \
      -OperationName CreateComparisonReport \
      -AdditionalOperationDirectory "$ADDITIONAL_OP_DIR" \
      -LabVIEWPath $LABVIEW_PATH \
      -LogToConsole TRUE \
      -vi1 "$VI_BASE" \
      -vi2 "$VI_HEAD" \
      -reportType "HTMLSingleFile" \
      -reportPath "$REPORT_PATH" \
      -o -c -nobdcosm \
      -Headless

    EXIT_CODE=$?

  elif [[ "$status" == "A" ]]; then
    # ---------- Added: print the new VI ----------
    VI_PATH="/workspace/$file"
    REPORT_PATH="$REPORT_DIR/print-report-$BASE_NAME.html"

    if [ ! -f "$VI_PATH" ]; then
      echo "Warning: Added VI not found: $VI_PATH, skipping."
      continue
    fi
    if ! is_vi_file "$VI_PATH"; then
      echo "Skipping $file: not a LabVIEW VI file."
      continue
    fi

    echo "Running LabVIEWCLI PrintToSingleFileHtml for added VI: $file"

    LabVIEWCLI \
      -OperationName PrintToSingleFileHtml \
      -AdditionalOperationDirectory "$ADDITIONAL_OP_DIR" \
      -LabVIEWPath $LABVIEW_PATH \
      -LogToConsole TRUE \
      -VI "$VI_PATH" \
      -OutputPath "$REPORT_PATH" \
      -o -c \
      -Headless

    EXIT_CODE=$?

  elif [[ "$status" == "D" ]]; then
    # ---------- Deleted: print the old VI ----------
    VI_PATH="/workspace/vi-base/$file"
    REPORT_PATH="$REPORT_DIR/print-report-$BASE_NAME.html"

    if [ ! -f "$VI_PATH" ]; then
      echo "Warning: Deleted VI not found in base: $VI_PATH, skipping."
      continue
    fi
    if ! is_vi_file "$VI_PATH"; then
      echo "Skipping $file: not a LabVIEW VI file."
      continue
    fi

    echo "Running LabVIEWCLI PrintToSingleFileHtml for deleted VI: $file"

    LabVIEWCLI \
      -OperationName PrintToSingleFileHtml \
      -AdditionalOperationDirectory "$ADDITIONAL_OP_DIR" \
      -LabVIEWPath $LABVIEW_PATH \
      -LogToConsole TRUE \
      -VI "$VI_PATH" \
      -OutputPath "$REPORT_PATH" \
      -o -c \
      -Headless

    EXIT_CODE=$?

  else
    echo "Skipping unrecognized status '$status' for: $file"
    continue
  fi

  if [ $EXIT_CODE -ne 0 ]; then
    echo "✖ LabVIEWCLI failed for $file (exit code $EXIT_CODE)"
    FAILED=$((FAILED + 1))
  elif [ ! -f "$REPORT_PATH" ]; then
    echo "✖ LabVIEWCLI exited 0 but report was not created: $REPORT_PATH"
    FAILED=$((FAILED + 1))
  else
    echo "✔ Report generated for $file"
  fi
done < "$CHANGED_FILES_FILE"
IFS="$ORIG_IFS"

chmod -R a+r "$REPORT_DIR"

if [ $FAILED -gt 0 ]; then
  echo "✖ $FAILED file(s) failed. Exiting with error."
  exit 1
else
  echo "✔ All reports generated successfully."
  exit 0
fi
