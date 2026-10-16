#!/bin/bash
# =============================================================================
# DevSecOps Security Gate Script
# Blocks deployment if any security scan fails.
#
# Usage: ./security-gate.sh <sast_result> <sca_result> <secret_result> <trivy_result>
# Each arg should be "pass" or "fail"
# =============================================================================
set -euo pipefail

if [ "$#" -ne 4 ]; then
  echo "Usage: $0 <sast_result> <sca_result> <secret_result> <trivy_result>" >&2
  exit 2
fi

for result in "$@"; do
  if [ "$result" != "pass" ] && [ "$result" != "fail" ]; then
    echo "Scan results must be either 'pass' or 'fail'." >&2
    exit 2
  fi
done

SAST_RESULT="$1"
SCA_RESULT="$2"
SECRET_RESULT="$3"
TRIVY_RESULT="$4"

FAILED=0

echo "================================================="
echo "   DevSecOps Security Gate Evaluation"
echo "================================================="
echo ""
echo " SAST (Bandit):       $SAST_RESULT"
echo " SCA (pip-audit):     $SCA_RESULT"
echo " Secret Scan:         $SECRET_RESULT"
echo " Container Scan:      $TRIVY_RESULT"
echo ""

if [ "$SAST_RESULT" = "fail" ]; then
  echo "🚫 SAST scan failed - high/medium severity issues found"
  FAILED=1
fi

if [ "$SCA_RESULT" = "fail" ]; then
  echo "🚫 SCA scan failed - vulnerable dependencies found"
  FAILED=1
fi

if [ "$SECRET_RESULT" = "fail" ]; then
  echo "🚫 Secret scan failed - leaked credentials detected"
  FAILED=1
fi

if [ "$TRIVY_RESULT" = "fail" ]; then
  echo "🚫 Container scan failed - CRITICAL/HIGH vulnerabilities in image"
  FAILED=1
fi

echo ""
if [ "$FAILED" -eq 1 ]; then
  echo "================================================="
  echo "  SECURITY GATE FAILED - Deployment BLOCKED"
  echo "================================================="
  exit 1
else
  echo "================================================="
  echo "  SECURITY GATE PASSED - Deployment authorized"
  echo "================================================="
  exit 0
fi
