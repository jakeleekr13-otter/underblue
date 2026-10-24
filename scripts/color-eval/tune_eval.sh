#!/bin/zsh
# Usage: tune_eval.sh <outName>
# Tuning scorecard: market before/after pairs + neutral ramp and real photos (no reference).
# Prints report.txt and writes sheets under $HT_EVAL_OUT/<outName>.
set -e
source ${0:A:h}/common.sh
O=$HT_EVAL_OUT/$1
build_eval $O
mkdir -p $O/market $O/real $O/guard $O/grain
M=$HT_EVAL_OUT/cache/market; mkdir -p $M/raw $M/ref
cp $HT_EVAL_MARKET/raw/*.png $M/raw/ && cp $HT_EVAL_MARKET/ref/*.png $M/ref/
python3 $HERE/make_neutral_ramp.py $M/raw/n_grey.png $M/ref/n_grey.png
real_links $HT_EVAL_OUT/cache/real
# Guard checks (docs/RestorationExperiments.md, Stage C): extra photos that are not in the real set.
G=$HT_EVAL_OUT/cache/guard; rm -rf $G && mkdir -p $G
ln -s $HT_EVAL_DATA/subjectpicker/DSC03696.JPG $G/g1.jpg
ln -s $HT_EVAL_DATA/tune/photo/plants/sargassum_green_water.png $G/pl1.png
ln -s $HT_EVAL_DATA/tune/photo/plants/kelp_teal_water.png $G/pl2.png
# Grain on flat bright sand (Stage C). Rendered at 1920 px, near the app preview (1600 px), with lossless PNG:
# at the default 640 px the grain does not show.
R=$HT_EVAL_OUT/cache/grain; rm -rf $R && mkdir -p $R
ln -s $HT_EVAL_DATA/eval/real/IMG_7262.JPG $R/r14.jpg
ln -s $HT_EVAL_DATA/eval/real/IMG_7255.JPG $R/r03.jpg
ln -s $HT_EVAL_DATA/eval/market/raw/m5.png $R/m5.png
ln -s $HT_EVAL_DATA/tune/photo/plants/sargassum_green_water.png $R/pl1.png
cd $O
./eval $M/raw $M/ref market.csv all market > market.log 2>&1
./eval $HT_EVAL_OUT/cache/real - real.csv all real > real.log 2>&1
./eval $G - guard.csv all guard > guard.log 2>&1
HT_EVAL_MAXDIM=1920 HT_EVAL_PNG=1 ./eval $R - grain.csv all grain > grain.log 2>&1
python3 $HERE/tune_report.py $O > report.txt
cat report.txt
