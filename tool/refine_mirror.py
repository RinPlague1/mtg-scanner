import numpy as np
# Mirror of the Dart algorithm. Input: RGB uint8 HxW analysis image, guide normalised rect.
def box_blur3(a):
    p=np.pad(a,((1,1),(1,1)),mode='edge'); s=np.zeros_like(a)
    for dy in range(3):
        for dx in range(3): s+=p[dy:dy+a.shape[0],dx:dx+a.shape[1]]
    return s/9
def edge_maps(rgb):
    H,W,_=rgb.shape
    ex=np.zeros((H,W),np.float32); ey=np.zeros((H,W),np.float32)
    for c in range(3):
        L=box_blur3(np.log(rgb[...,c].astype(np.float32)+8.0))
        gx=np.zeros_like(L); gy=np.zeros_like(L)
        gx[:,1:-1]=L[:,2:]-L[:,:-2]
        gy[1:-1,:]=L[2:,:]-L[:-2,:]
        ex=np.maximum(ex,np.abs(gx)); ey=np.maximum(ey,np.abs(gy))
    return ex,ey
SLOPES=np.tan(np.deg2rad(np.linspace(-6,6,13)))
def side_profile(E, horizontal, pos_lo, pos_hi, span_lo, span_hi, slopes=SLOPES):
    """horizontal: line y = p + t*(x-mid). Returns positions, best scores, best slope."""
    H,W=E.shape
    mid=(span_lo+span_hi)/2
    span=np.arange(max(0,int(np.ceil(span_lo))),int(np.floor(span_hi))+1,2)
    pos=np.arange(max(1,int(np.ceil(pos_lo))),min((H if horizontal else W)-2,int(np.floor(pos_hi)))+1)
    best=np.zeros(len(pos)); bt=np.zeros(len(pos))
    for i,p in enumerate(pos):
        for t in slopes:
            q=np.rint(p+t*(span-mid)).astype(int)
            lim=(H if horizontal else W)
            ok=(q>=0)&(q<lim)
            v=E[q[ok],span[ok]] if horizontal else E[span[ok],q[ok]]
            s=v.mean() if len(v) else 0
            if s>best[i]: best[i]=s; bt[i]=t
    return pos,best,bt
def pick_outermost(pos,score,outer_first,min_contrast=0.07):
    n=len(score)
    gfloor=np.percentile(score,15); gspread=np.percentile(score,25)-np.percentile(score,5)+1e-6
    for k in range(n):
        i=k if outer_first else n-1-k
        if i==0 or i==n-1: continue
        if not (score[i]>=score[i-1] and score[i]>=score[i+1]): continue
        # baseline from the mat side of the candidate (3..11 px further out)
        if outer_first: win=score[max(0,i-11):max(0,i-2)]
        else: win=score[i+3:i+12]
        if len(win)>=4:
            base=np.median(win); spread=1.4826*np.median(np.abs(win-base))+1e-6
        else:
            # too close to the band's outer end: use the strip just inside
            # (the border itself on a black-bordered card)
            win=score[i+3:i+10] if outer_first else score[max(0,i-9):max(0,i-2)]
            base=np.median(win); spread=1.4826*np.median(np.abs(win-base))+1e-6
        if score[i]>=base+max(6*spread,min_contrast):
            return i,(score[i]-base)/spread
    return None,0
def refine(rgb, guide, band=0.12):
    H,W,_=rgb.shape
    ex,ey=edge_maps(rgb)
    gx0,gy0,gx1,gy1=guide[0]*W,guide[1]*H,guide[2]*W,guide[3]*H
    gw,gh=gx1-gx0,gy1-gy0
    sides={}
    for side in ['top','bottom','left','right']:
        hor= side in ('top','bottom')
        g={'top':gy0,'bottom':gy1,'left':gx0,'right':gx1}[side]
        d=band*(gh if hor else gw)
        if hor: sl,sh=gx0+0.15*gw,gx1-0.15*gw
        else: sl,sh=gy0+0.15*gh,gy1-0.15*gh
        sides[side]=(hor,g-d,g+d,sl,sh)
    # 1) global rotation estimate
    best_a,best_s=0,-1
    for a in np.arange(-6,6.01,0.5):
        t=np.tan(np.deg2rad(a)); tot=0
        for side,(hor,lo,hi,sl,sh) in sides.items():
            _,sc,_=side_profile(ey if hor else ex,hor,lo,hi,sl,sh,[t if hor else -t])
            tot+=sc.max()-np.percentile(sc,15)
        if tot>best_s: best_s,best_a=tot,a
    lines={}
    for side,(hor,lo,hi,sl,sh) in sides.items():
        sgn=1 if hor else -1
        slopes=[np.tan(np.deg2rad(sgn*best_a+d)) for d in (-1,-0.5,0,0.5,1)]
        pos,sc,bt=side_profile(ey if hor else ex,hor,lo,hi,sl,sh,slopes)
        i,conf=pick_outermost(pos,sc, side in ('top','left'))
        lines[side]=None if i is None else (pos[i],bt[i],(sl+sh)/2,conf)
    return lines
def quad_from_lines(lines, guide, W, H):
    gx0,gy0,gx1,gy1=guide[0]*W,guide[1]*H,guide[2]*W,guide[3]*H
    gmid_x=(gx0+gx1)/2; gmid_y=(gy0+gy1)/2
    L={}
    for s,g in (('top',gy0),('bottom',gy1),('left',gx0),('right',gx1)):
        mid = gmid_x if s in('top','bottom') else gmid_y
        L[s]=lines[s] if lines[s] else (g,0.0,mid,0)
    # intersect y = pt + tt*(x-mt) with x = pl + tl*(y-ml)
    def inter(h,v):
        p1,t1,m1,_=h; p2,t2,m2,_=v
        # x = p2 + t2*(y-m2); y = p1 + t1*(x-m1)
        x=(p2 + t2*(p1 - t1*m1 - m2))/(1 - t2*t1)
        y=p1+t1*(x-m1); return (x,y)
    return [inter(L['top'],L['left']),inter(L['top'],L['right']),inter(L['bottom'],L['right']),inter(L['bottom'],L['left'])]
