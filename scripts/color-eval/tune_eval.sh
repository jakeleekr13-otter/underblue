#!/bin/zsh
# Usage: tune_eval.sh <outName>
# Tuning scorecard: market before/after pairs + neutral ramp and real photos (no reference).
# Prints report.txt and writes sheets under $HT_EVAL_OUT/<outName>.
set -e
source ${0:A:h}/common.sh
O=$HT_EVAL_OUT/$1
build_eval $O
mkdir -p $O/market $O/real $O/gear
M=$HT_EVAL_OUT/cache/market; mkdir -p $M/raw $M/ref
cp $HT_EVAL_MARKET/raw/*.png $M/raw/ && cp $HT_EVAL_MARKET/ref/*.png $M/ref/
python3 $HERE/make_neutral_ramp.py $M/raw/n_grey.png $M/ref/n_grey.png
real_links $HT_EVAL_OUT/cache/real
# Black gear check (docs/RestorationExperiments.md, Stage C): extra photos that are not in the real set.
G=$HT_EVAL_OUT/cache/gear; rm -rf $G && mkdir -p $G
ln -s $HT_EVAL_DATA/subjectpicker/DSC03696.JPG $G/g1.jpg
cd $O
./eval $M/raw $M/ref market.csv all market > market.log 2>&1
./eval $HT_EVAL_OUT/cache/real - real.csv all real > real.log 2>&1
./eval $G - gear.csv all gear > gear.log 2>&1
python3 $HERE/tune_report.py $O > report.txt
cat report.txt
