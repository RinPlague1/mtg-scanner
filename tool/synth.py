import numpy as np, cv2
CW, CH = 630, 880  # card template px (63x88mm *10)
def card_template(frame=(38,36,40), border=(12,12,14), textbox=(205,200,190), art=(90,60,120), namebar=(140,135,130), black_border=True, glare=False, rng=None):
    c = np.zeros((CH,CW,3),np.uint8); c[:] = border if black_border else (220,220,220)
    b=int(0.045*CW)
    c[b:CH-b, b:CW-b] = frame
    # name bar
    c[int(0.045*CH):int(0.10*CH), int(0.065*CW):int(0.935*CW)] = namebar
    cv2.putText(c,"Sheoldred the Apocalypse",(int(0.085*CW),int(0.088*CH)),cv2.FONT_HERSHEY_SIMPLEX,0.9,(10,10,10),2)
    c[int(0.11*CH):int(0.555*CH), int(0.075*CW):int(0.925*CW)] = art
    c[int(0.565*CH):int(0.625*CH), int(0.065*CW):int(0.935*CW)] = namebar
    c[int(0.635*CH):int(0.90*CH), int(0.075*CW):int(0.925*CW)] = textbox
    cv2.putText(c,"0107 M",(int(0.05*CW),int(0.955*CH)),cv2.FONT_HERSHEY_SIMPLEX,0.6,(230,230,230),1)
    cv2.putText(c,"DMU * EN",(int(0.05*CW),int(0.98*CH)),cv2.FONT_HERSHEY_SIMPLEX,0.6,(230,230,230),1)
    c=c.astype(np.float32)
    if glare:
        yy,xx=np.mgrid[0:CH,0:CW]; g=np.exp(-(((xx-0.4*CW)/90)**2+((yy-0.07*CH)/40)**2))
        c = c*(1-g[...,None]) + 255*g[...,None]
    return c
def scene(W=1080,H=1920, mat=(22,26,34), card_kw={}, offset=(0,0), angle=0.0, scale=1.0, noise=6, seed=0, texture=True):
    rng=np.random.default_rng(seed)
    img=np.zeros((H,W,3),np.float32); img[:]=mat
    if texture:
        n=cv2.GaussianBlur(rng.normal(0,1,(H,W)).astype(np.float32),(0,0),6)*8
        img+=n[...,None]
    c=card_template(**card_kw)
    # guide: card width 80% of W centred
    gw=0.8*W; gh=gw*88/63; gx0=(W-gw)/2; gy0=(H-gh)/2
    w=gw*scale; h=gh*scale
    cx=W/2+offset[0]; cy=H/2+offset[1]
    src=np.float32([[0,0],[CW,0],[CW,CH],[0,CH]])
    a=np.deg2rad(angle); R=np.array([[np.cos(a),-np.sin(a)],[np.sin(a),np.cos(a)]])
    pts=np.array([[-w/2,-h/2],[w/2,-h/2],[w/2,h/2],[-w/2,h/2]])@R.T+[cx,cy]
    M=cv2.getPerspectiveTransform(src,pts.astype(np.float32))
    warped=cv2.warpPerspective(c,M,(W,H),flags=cv2.INTER_LINEAR)
    mask=cv2.warpPerspective(np.ones((CH,CW),np.float32),M,(W,H))
    img=img*(1-mask[...,None])+warped*mask[...,None]
    img+=rng.normal(0,noise,img.shape)
    img=np.clip(img,0,255).astype(np.uint8)
    guide=(gx0/W,gy0/H,(gx0+gw)/W,(gy0+gh)/H)
    return img, pts, guide
