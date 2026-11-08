// poses.js
// Mannequin 3P (#107) : rig aux cotes du StarterCharacter, tenues d'arme, états de déplacement.
// Source unique de la planche (planche.html) et de l'export Luau (export_pose.js).
// Repère Roblox : x droite, y haut, -z avant ; origine = centre de la HumanoidRootPart, sol à y = -4,77.

// ── Maths 3D (repère Roblox : x droite, y haut, -z avant) ─────────────────
const D=Math.PI/180;
const M={
 mul(a,b){const r=[];for(let i=0;i<3;i++)for(let j=0;j<3;j++)r.push(a[i*3]*b[j]+a[i*3+1]*b[3+j]+a[i*3+2]*b[6+j]);return r},
 v(m,p){return[m[0]*p[0]+m[1]*p[1]+m[2]*p[2],m[3]*p[0]+m[4]*p[1]+m[5]*p[2],m[6]*p[0]+m[7]*p[1]+m[8]*p[2]]},
 x(a){a*=D;const c=Math.cos(a),s=Math.sin(a);return[1,0,0,0,c,-s,0,s,c]},
 y(a){a*=D;const c=Math.cos(a),s=Math.sin(a);return[c,0,s,0,1,0,-s,0,c]},
 z(a){a*=D;const c=Math.cos(a),s=Math.sin(a);return[c,-s,0,s,c,0,0,0,1]},
 cols(x,y,z){return[x[0],y[0],z[0],x[1],y[1],z[1],x[2],y[2],z[2]]},
 t(m){return[m[0],m[3],m[6],m[1],m[4],m[7],m[2],m[5],m[8]]},
 I:[1,0,0,0,1,0,0,0,1]};
// Cette méthode permet d'enchaîner des rotations (produit de gauche à droite) lorsqu'on compose une articulation.
const ch=(...ms)=>ms.reduce((a,b)=>M.mul(a,b));
const V={add:(a,b)=>[a[0]+b[0],a[1]+b[1],a[2]+b[2]],sub:(a,b)=>[a[0]-b[0],a[1]-b[1],a[2]-b[2]],mul:(a,s)=>[a[0]*s,a[1]*s,a[2]*s],
 dot:(a,b)=>a[0]*b[0]+a[1]*b[1]+a[2]*b[2],cross:(a,b)=>[a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0]],len:a=>Math.hypot(a[0],a[1],a[2])};
V.norm=a=>V.mul(a,1/(V.len(a)||1));
const col=(m,i)=>[m[i],m[3+i],m[6+i]];

// ── Couleurs (celles du jeu, éclaircies pour la lecture) ─────────────────
const C={skin:[214,162,126],tor:[104,116,82],torD:[90,100,72],arm:[104,116,82],hand:[86,96,68],leg:[86,90,100],foot:[62,64,72],visor:[38,42,48],
 awp:[50,72,54],metal:[56,58,64],scope:[30,32,36],kh:[40,42,46],kg:[116,118,124],kb:[214,220,228]};

// Cette méthode permet de décrire un pavé (membre du rig) lorsqu'on construit le personnage.
const box=(p,R,s,c)=>({k:'b',p,R,s,c});
// Cette méthode permet de décrire un profil extrudé (pièce d'arme) lorsqu'on construit l'arme tenue.
const prism=(p,R,prof,t,c)=>({k:'p',p,R,prof,t,c,w:true});

// Cette méthode permet de lister les faces d'une pièce (pavé ou profil extrudé) lorsqu'on la dessine.
function facesOf(o){
 const F=[];
 if(o.k==='b'){
  for(let i=0;i<3;i++){const j=(i+1)%3,k=(i+2)%3;const ai=col(o.R,i),aj=col(o.R,j),ak=col(o.R,k);
   for(const sg of[1,-1]){const n=V.mul(ai,sg);const c=V.add(o.p,V.mul(n,o.s[i]/2));const hj=V.mul(aj,o.s[j]/2),hk=V.mul(ak,o.s[k]/2);
    F.push({n,pts:[V.add(V.add(c,hj),hk),V.add(V.sub(c,hj),hk),V.sub(V.sub(c,hj),hk),V.sub(V.add(c,hj),hk)],c:o.c});}}
 }else{
  const P=o.prof;let A=0;for(let i=0;i<P.length;i++){const a=P[i],b=P[(i+1)%P.length];A+=a[0]*b[1]-b[0]*a[1];}
  const sg=A>=0?1:-1;const W=(u,v,x)=>V.add(o.p,M.v(o.R,[x,v,-u]));const ax=col(o.R,0);
  F.push({n:ax,pts:P.map(q=>W(q[0],q[1],o.t/2)),c:o.c});
  F.push({n:V.mul(ax,-1),pts:P.map(q=>W(q[0],q[1],-o.t/2)),c:o.c});
  for(let i=0;i<P.length;i++){const a=P[i],b=P[(i+1)%P.length];const du=b[0]-a[0],dv=b[1]-a[1];
   F.push({n:M.v(o.R,V.norm([0,-sg*du,-sg*dv])),pts:[W(a[0],a[1],o.t/2),W(b[0],b[1],o.t/2),W(b[0],b[1],-o.t/2),W(a[0],a[1],-o.t/2)],c:o.c});}
 }
 return F;
}

// ── Armes (silhouettes simplifiées, cotes du .rbxm à l'échelle 3P) ───────
// Repère : origine = centre de la main droite, u vers le canon / la pointe, v vers le haut / le dos de la lame.
// Cette méthode permet de décrire un rectangle de profil lorsqu'on dessine une pièce d'arme droite.
const RECT=(u0,u1,v0,v1)=>[[u0,v0],[u1,v0],[u1,v1],[u0,v1]];
// Cette méthode permet de décrire l'AWP en profils extrudés à l'échelle 3P s lorsqu'on construit l'arme tenue.
function AWP(s){const k=s/0.5;const S=a=>a.map(([u,v])=>[u*k,v*k]);return[
 {prof:S([[-1.65,-0.10],[-0.75,0.12],[-0.2,0.12],[-0.22,-0.24],[0.08,-0.22],[0.1,0.15],[0.8,0.2],[2.05,0.24],[2.05,0.42],[-0.15,0.42],[-1.4,0.48],[-1.65,0.46]]),t:0.2*k,c:C.awp},
 {prof:S(RECT(2.0,3.42,0.26,0.40)),t:0.14*k,c:C.metal},{prof:S(RECT(3.28,3.44,0.22,0.44)),t:0.2*k,c:C.metal},
 {prof:S(RECT(0.35,0.65,-0.1,0.18)),t:0.13*k,c:C.metal},{prof:S(RECT(0,1.7,0.53,0.71)),t:0.18*k,c:C.scope},
 {prof:S(RECT(-0.05,0.25,0.48,0.76)),t:0.26*k,c:C.scope},{prof:S(RECT(1.35,1.72,0.47,0.77)),t:0.3*k,c:C.scope},
 {prof:S(RECT(0.3,0.42,0.4,0.55)),t:0.12*k,c:C.metal},{prof:S(RECT(1.0,1.12,0.4,0.55)),t:0.12*k,c:C.metal}];}
// Cette méthode permet de décrire la M9 (manche, garde, lame à dents) à l'échelle 3P s lorsqu'on construit l'arme tenue.
function KNIFE(s){const S=a=>a.map(([u,v])=>[u*s,v*s]);
 const blade=[[0.62,-0.24],[2.6,-0.24],[3.07,-0.02],[2.45,0.22]];
 for(let u=2.0;u>1.0;u-=0.12){blade.push([u,0.22],[u-0.06,0.29]);}
 blade.push([1.0,0.22],[0.62,0.22]);
 return[{prof:S([[-0.72,0],[-0.65,-0.2],[0.5,-0.19],[0.5,0.19],[-0.65,0.2]]),t:0.32*s,c:C.kh},
  {prof:S(RECT(0.5,0.62,-0.42,0.36)),t:0.2*s,c:C.kg},{prof:S(blade),t:0.09*s,c:C.kb}];}
const KNIFE_TIP=3.07, CHAR_H=7.94;

// ── Bras : cinématique directe et inverse (cotes du StarterCharacter) ─────
const A_UP=Math.hypot(0.79,1.16), A_LO=1.41, A_MAX=Math.hypot(0.79,1.16+1.41);
// Cette méthode permet d'ajouter un bras (haut, avant-bras, main) lorsque l'orientation de l'épaule est connue.
function armParts(parts,side,S,R,el){
 parts.push(box(V.add(S,M.v(R,[side*0.79,-0.63,0])),R,[1.59,1.86,1.59],C.arm));
 const E=V.add(S,M.v(R,[side*0.79,-1.16,0]));const Rf=M.mul(R,M.x(el));
 parts.push(box(V.add(E,M.v(Rf,[0,-0.41,0])),Rf,[1.59,1.67,1.59],C.arm));
 const H=V.add(E,M.v(Rf,[0,-1.41,0]));parts.push(box(H,Rf,[1.59,0.48,1.59],C.hand));
 return{H,Rh:Rf};
}
// Cette méthode permet de placer la main sur une cible (IK deux os, coude orienté par pole) lorsqu'elle tient l'arme ;
// renvoie l'orientation de l'épaule, la flexion du coude et la distance manquante si la cible est hors de portée.
function armIK(side,S,T,pole){
 const a=A_UP,b=A_LO;const d=V.sub(T,S);let L=V.len(d);const u=V.norm(d);let miss=0;
 // portée réelle : bras tendu (coude à 0), le pivot de l'épaule étant décalé de 0,79 stud de l'axe du bras
 if(L>A_MAX-1e-3){miss=L-A_MAX;L=A_MAX-1e-3;}
 const cA=(a*a+L*L-b*b)/(2*a*L),sA=Math.sqrt(Math.max(0,1-cA*cA));
 const p=V.norm(V.sub(pole,V.mul(u,V.dot(pole,u))));
 const E=V.add(S,V.add(V.mul(u,a*cA),V.mul(p,a*sA)));const Tc=V.add(S,V.mul(u,L));
 const u1=V.norm(V.sub(E,S)),v2=V.norm(V.sub(Tc,E));
 const lx=side*0.79/a,ly=-1.16/a;
 const w0=V.sub(u1,V.mul(v2,V.dot(u1,v2)));const m=V.len(w0);const w=V.norm(w0);const e2=V.cross(v2,w);
 let best=null;
 for(const sg of[1,-1]){const phi=sg*Math.acos(Math.max(-1,Math.min(1,lx/m)));
  const X=V.add(V.mul(w,Math.cos(phi)),V.mul(e2,Math.sin(phi)));const Y=V.norm(V.mul(V.sub(u1,V.mul(X,lx)),1/ly));const Z=V.cross(X,Y);
  const el=Math.atan2(-V.dot(v2,Z),-V.dot(v2,Y))/D;const score=el>=-1&&el<=181?1:0;
  if(!best||score>best.score)best={R:M.cols(X,Y,Z),el,score};}
 return{R:best.R,el:best.el,miss};
}

// ── Tenues ──────────────────────────────────────────────────────────────
const HOLDS={
 F0:{type:'awp',arms:{R:{fwd:90,yaw:10},L:{fwd:90,yaw:-35}}},
 F1:{type:'awp',scale:0.7,yaw:-40,gunRoot:{g:[0.5,1.3,-1.3],pitch:0}},
 F2:{type:'awp',yaw:-35,gunRoot:{g:[0.7,0.5,-1.25],pitch:-28}},
 C0:{type:'knife',scale:0.6,knife:'C0',arms:{R:{fwd:60}}},
 C1:{type:'knife',scale:1.0,tilt:15,leftFreeOnGround:true,arms:{R:{fwd:25,out:8,el:70},L:{fwd:14,out:10,el:35}}},
 C2:{type:'knife',scale:1.0,tilt:-30,arms:{R:{fwd:38,out:4,yaw:14,el:100},L:{fwd:32,out:6,yaw:-28,el:112}}},
};
for(const H of Object.values(HOLDS))if(H.gunRoot){const Rt0=M.y(H.yaw);const Rw0=M.x(H.gunRoot.pitch||0);
 H._local={Rwl:M.mul(M.t(Rt0),Rw0),Gl:M.v(M.t(Rt0),V.sub(H.gunRoot.g,[0,0.32,0]))};}

// ── États de déplacement (jambes et bras R15 approximés) ─────────────────
// Cette méthode permet de décrire une pose de bras (avant, écart, coude, rotation) lorsqu'on définit un état.
const A=(fwd,out,el,yaw=0)=>({fwd,out,el,yaw});
// Cette méthode permet de mélanger deux poses de bras lorsqu'un bras passe de libre à tenu (k = 0 → a, 1 → b).
const lerpArm=(a,b,k)=>({fwd:L(a.fwd||0,b.fwd||0,k),out:L(a.out||0,b.out||0,k),el:L(a.el||0,b.el||0,k),yaw:L(a.yaw||0,b.yaw||0,k)});
// Cette méthode permet d'interpoler linéairement deux nombres lorsqu'on mélange deux poses.
function L(a,b,k){return a+(b-a)*k}
const ST={
 idle:{legs:{R:[0,0],L:[0,0]},arms:{R:A(4,5,10),L:A(4,5,10)}},
 run1:{lean:9,legs:{R:[32,14],L:[-26,58]},arms:{R:A(-38,6,40),L:A(48,6,70)}},
 run2:{lean:9,legs:{R:[0,20],L:[40,105]},arms:{R:A(-4,6,45),L:A(8,6,50)}},
 run3:{lean:9,legs:{R:[-26,58],L:[32,14]},arms:{R:A(48,6,70),L:A(-38,6,40)}},
 run4:{lean:9,legs:{R:[40,105],L:[0,20]},arms:{R:A(8,6,50),L:A(-4,6,45)}},
 jump1:{air:0.5,lean:4,legs:{R:[-14,20],L:[6,12]},arms:{R:A(155,15,12),L:A(155,15,12)}},
 jump2:{air:2.0,legs:{R:[55,90],L:[38,100]},arms:{R:A(165,12,10),L:A(165,12,10)}},
 jump3:{air:1.1,legs:{R:[26,28],L:[6,48]},arms:{R:A(140,25,15),L:A(140,25,15)}},
 fall:{air:1.3,legs:{R:[18,30],L:[-8,52]},arms:{R:A(115,50,20),L:A(115,50,20)}},
};
ST.surf=ST.fall;ST.crouch=ST.idle;

// Cette méthode permet de construire le personnage d'une tenue dans un état lorsqu'on dessine une vignette ;
// mode 'today' compose la pose actuelle (C0 des épaules) avec la piste R15, comme en jeu aujourd'hui.
function build(holdKey,stKey,mode){
 const H=HOLDS[holdKey],st=typeof stKey==='string'?ST[stKey]:stKey;const parts=[],info={miss:{R:0,L:0}};
 const airW=st.airW!==undefined?st.airW:(st.air!==undefined?1:0);
 const Rr=M.x(-(st.lean||0));let minY=Infinity;
 for(const side of[1,-1]){const[th,kn]=st.legs[side>0?'R':'L'];
  const hip=M.v(Rr,[side*0.79,-1.59,0]);const R1=ch(Rr,M.x(th),M.z(side*2));
  parts.push(box(V.add(hip,M.v(R1,[0,-0.67,0])),R1,[1.59,1.93,1.59],C.leg));
  const knee=V.add(hip,M.v(R1,[0,-1.31,0]));const R2=M.mul(R1,M.x(-kn));
  parts.push(box(V.add(knee,M.v(R2,[0,-0.6,0])),R2,[1.59,1.89,1.59],C.leg));
  const ank=V.add(knee,M.v(R2,[0,-1.47,0]));const R3=M.mul(R2,M.x(kn-th));
  const fb=box(V.add(ank,M.v(R3,[0,-0.16,-0.12])),R3,[1.59,0.48,1.75],C.foot);parts.push(fb);
  for(const f of facesOf(fb))for(const p of f.pts)minY=Math.min(minY,p[1]);}
 parts.push(box(M.v(Rr,[0,-1.27,0]),Rr,[3.18,0.64,1.59],C.torD));
 const yaw=mode==='today'?0:(H.yaw||0);const Rt=ch(Rr,M.y(yaw));
 const UT=V.add(M.v(Rr,[0,-0.95,0]),M.v(Rt,[0,1.27,0]));
 parts.push(box(UT,Rt,[3.18,2.54,1.59],C.tor));
 // la tête reste face au regard quand la tenue tourne la taille (Neck compense Waist)
 const Rh=ch(Rt,M.y(-yaw));const head=V.add(UT,M.v(Rt,[0,2.06,0]));parts.push(box(head,Rh,[1.9,1.6,1.6],C.skin));
 parts.push(box(V.add(head,M.v(Rh,[0,0.12,-0.81])),Rh,[1.35,0.34,0.04],C.visor));
 const S={R:V.add(UT,M.v(Rt,[1.59,0.89,0])),L:V.add(UT,M.v(Rt,[-1.59,0.89,0]))};
 if(H.gunRoot&&mode!=='today'){
  const Rw=M.mul(Rt,H._local.Rwl),G=V.add(UT,M.v(Rt,H._local.Gl));
  const k=(H.scale||0.5)/0.5;const tL=V.add(G,M.v(Rw,[0,-0.02*k,-1.26*k]));
  info.arms={};info.Rt=Rt;info.gun={G,Rw};
  for(const[sd,T]of[['R',G],['L',tL]]){const side=sd==='R'?1:-1;const r=armIK(side,S[sd],T,M.v(Rt,[side*0.7,-1,0.45]));info.miss[sd]=r.miss;
   info.arms[sd]={R:r.R,el:r.el,...armParts(parts,side,S[sd],r.R,r.el)};}
  for(const w of AWP(H.scale||0.5))parts.push(prism(G,Rw,w.prof,w.t,w.c));
 }else{
  const hands={};
  for(const sd of['R','L']){const side=sd==='R'?1:-1;const ha=H.arms&&H.arms[sd];let a,pre=M.I;
   if(mode==='today'){a=st.arms[sd];if(ha)pre=ch(M.y(ha.yaw||0),M.x(ha.fwd||0),M.z(side*(ha.out||0)));}
   else if(!ha)a=st.arms[sd];
   // bras gauche du couteau : libre au sol (piste de déplacement), tenu en l'air, fondu selon airW
   else if(sd==='L'&&H.leftFreeOnGround)a=lerpArm(st.arms[sd],ha,airW);
   else a=ha;
   const R=ch(Rt,pre,M.y(a.yaw||0),M.x(a.fwd||0),M.z(side*(a.out||0)));hands[sd]={R,el:a.el||0,...armParts(parts,side,S[sd],R,a.el||0)};}
  info.arms=hands;info.Rt=Rt;
  const h=hands.R;
  if(H.type==='awp'){const Rw=M.mul(h.Rh,M.cols([1,0,0],[0,0,-1],[0,1,0]));
   const G=V.add(V.add(h.H,M.v(h.Rh,[0,-0.2,0])),M.v(Rw,[0,-0.305,0.685]));
   for(const w of AWP(0.5))parts.push(prism(G,Rw,w.prof,w.t,w.c));}
  else{let ax,sp,off=[0,0,0];
   if(H.knife==='C0'){ax=[0,0,-1];sp=[0,1,0];off=[0,-0.13,0];}
   else{const t=H.tilt*D;ax=[0,-Math.cos(t),-Math.sin(t)];sp=[0,Math.sin(t),-Math.cos(t)];}
   info.knife={ax,sp,off};const z=V.mul(ax,-1),x=V.cross(sp,z);const Rk=M.mul(h.Rh,M.cols(x,sp,z));
   for(const w of KNIFE(H.scale))parts.push(prism(V.add(h.H,M.v(h.Rh,off)),Rk,w.prof,w.t,w.c));
   const half=[0.795,0.24,0.795];let exit=Infinity;for(let i=0;i<3;i++)if(Math.abs(ax[i])>1e-6)exit=Math.min(exit,(half[i]-Math.sign(ax[i])*off[i])/Math.abs(ax[i]));
   info.visible=KNIFE_TIP*H.scale-exit;info.total=3.72*H.scale;}
 }
 const off=(1-airW)*(-4.77-minY)+airW*(st.air||0);
 for(const p of parts)p.p=[p.p[0],p.p[1]+off,p.p[2]];
 const air=airW*(st.air||0);
 return{parts,info,shadowR:2.4-0.3*air,shadowO:0.14-0.035*air};
}

if(typeof module!=='undefined')module.exports={M,V,C,HOLDS,ST,build,facesOf,AWP,KNIFE,CHAR_H,col};
