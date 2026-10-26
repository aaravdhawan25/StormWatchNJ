// a phone or tablet, which can place calls and send texts
export const canCallAndText = () =>
  /iPhone|iPad|iPod|Android/i.test(navigator.userAgent) || (navigator.platform === "MacIntel" && navigator.maxTouchPoints > 1);

// whether this device has a camera at all
export async function hasCamera(): Promise<boolean> {
  try {
    const devices = await navigator.mediaDevices?.enumerateDevices();
    return !!devices?.some(d => d.kind === "videoinput");
  } catch { return false; }
}

// true when the person has blocked the camera for this site
export async function cameraBlocked(): Promise<boolean> {
  try { return (await navigator.permissions.query({ name: "camera" as PermissionName })).state === "denied"; }
  catch { return false; }
}
