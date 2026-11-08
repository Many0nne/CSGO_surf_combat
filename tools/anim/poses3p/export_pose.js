// export_pose.js
// Exporte les tenues validées de la planche (F1 fusil, C1 couteau) en données Luau pour WeaponThirdPerson.POSES
// et WeaponConfig.ThirdPerson.Grip : Transform de chaque Motor6D (repère Roblox) et grip de l'arme dans la main droite.
// Usage : node tools/anim/poses3p/export_pose.js
const P = require("./poses.js");
const { M, V, col } = P;

// Cette méthode permet d'écrire un CFrame Luau (12 composantes) lorsqu'on exporte une rotation et une position.
function cf(R, p = [0, 0, 0]) {
	const n = (x) => (Math.abs(x) < 5e-6 ? 0 : +x.toFixed(5));
	return `CFrame.new(${[...p, ...R].map(n).join(", ")})`;
}
// Cette méthode permet de décrire la tenue (Transform par articulation) lorsqu'on exporte une pose de la planche.
function joints(key, armSides, airSides) {
	const f = P.build(key, "idle", "hold");
	const out = {};
	const Rt = f.info.Rt;
	const yaw = P.HOLDS[key].yaw || 0;
	if (yaw) {
		out.Waist = M.y(yaw);
		out.Neck = M.y(-yaw); // la tête reste face au regard
	}
	for (const sd of armSides.concat(airSides)) {
		const side = sd === "R" ? "Right" : "Left";
		const arm = f.info.arms[sd];
		out[side + "Shoulder"] = M.mul(M.t(Rt), arm.R);
		out[side + "Elbow"] = M.x(arm.el);
		out[side + "Wrist"] = M.I;
	}
	return { f, out };
}
// Cette méthode permet d'écrire les articulations d'une tenue en lignes Luau lorsqu'on produit POSES.
const fmt = (o) => Object.entries(o).map(([k, R]) => `\t\t\t${k} = ${cf(R)},`).join("\n");

// Cette méthode permet de refuser une tenue inexportable lorsqu'une main n'atteint pas l'arme ou qu'un coude se plie
// à l'envers (rotation incohérente avec le rig).
function check(key, f) {
	for (const sd of Object.keys(f.info.arms || {})) {
		const arm = f.info.arms[sd];
		if ((f.info.miss[sd] || 0) > 1e-3) throw new Error(`${key} : main ${sd} hors de portée de ${f.info.miss[sd].toFixed(2)} stud`);
		if (arm.el < 2) throw new Error(`${key} : coude ${sd} trop tendu (${arm.el.toFixed(1)}°), rapprocher l'arme`);
	}
}

// Fusil F1 : les deux bras et la taille tenus en permanence.
const rifle = joints("F1", ["R", "L"], []);
check("F1", rifle.f);
// Couteau C1 : bras droit toujours tenu ; bras gauche tenu seulement en l'air (libre au sol, Q4).
const knifeR = joints("C1", ["R"], []);
const knifeAir = P.build("C1", { ...P.ST.fall, airW: 1 }, "hold");
const knifeL = {
	LeftShoulder: M.mul(M.t(knifeAir.info.Rt), knifeAir.info.arms.L.R),
	LeftElbow: M.x(knifeAir.info.arms.L.el),
	LeftWrist: M.I,
};

// Grip AWP : poignée (Handle) dans le repère de la main droite. Handle : X = canon, Y = dessus.
const { G, Rw } = rifle.f.info.gun;
const h = rifle.f.info.arms.R;
const k = (P.HOLDS.F1.scale || 0.5) / 0.5; // décalages relevés sur l'AWP à l'échelle 0,5
const handle = V.add(G, M.v(Rw, [0, 0.305 * k, -0.685 * k]));
const xl = col(Rw, 0), yl = col(Rw, 1), zl = col(Rw, 2);
const handleR = M.cols(V.mul(zl, -1), yl, xl);
const RhT = M.t(h.Rh);
const awpGrip = cf(M.mul(RhT, handleR), M.v(RhT, V.sub(handle, h.H)));

// Grip couteau : centre du mesh = centre du manche + 1,21 × échelle le long de l'axe. Handle : Z = pointe, X = tranchant.
const { ax, sp, off } = knifeR.f.info.knife;
const s = P.HOLDS.C1.scale;
const Zh = ax, Xh = V.mul(sp, -1), Yh = V.cross(Zh, Xh);
const knifeGrip = cf(M.cols(Xh, Yh, Zh), V.add(off, V.mul(ax, 1.21 * s)));

console.log(`-- WeaponConfig.Weapons.AWP.ThirdPerson.Scale = ${P.HOLDS.F1.scale}
-- WeaponThirdPerson.POSES (généré par tools/anim/poses3p/export_pose.js)
	Rifle = {
		Joints = {
${fmt(rifle.out)}
		},
	},
	Melee = {
		Joints = {
${fmt(knifeR.out)}
		},
		AirJoints = {
${fmt(knifeL)}
		},
	},

-- WeaponConfig.Weapons.AWP.ThirdPerson.Grip
${awpGrip}
-- WeaponConfig.Weapons.M9Bayonet.ThirdPerson (Scale = ${s})
${knifeGrip}`);
