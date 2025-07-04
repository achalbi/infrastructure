#!/bin/bash

# This script deploys using helmfile in the charts directory
# Usage: ./deploy.sh [helmfile arguments]

set -e

cd ../charts

helmfile -f helmfile.yaml apply 
