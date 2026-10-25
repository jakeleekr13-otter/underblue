# spec <way A|B|C> <k>
spec() { python3 -c "
k=$2; w='$1'
if w=='A': v=[min(0.9,0.18*k),0.15,0.6,0.6,0.5]
elif w=='B': v=[min(0.9,0.18*k),0.15*k,0.6*k,0.6*k,0.5]
else: v=[min(0.9,0.25*k),0.15*k,0.6*min(1,k),0.6*k,0.25]
s,c,d,cl,pv=v
print(','.join(str(round(x,4)) for x in [s,1.3,0.85,0.05,0.333333,c,d,cl,0.4,0.5,0.8,0,0,0.85,0.85,pv]))"; }
