import LogoMark from "./LogoMark";
import SignOutButton from "./SignOutButton";

import { T } from "@/components/T";
/** Shown instead of the app when a login has no role yet, or has been turned off. */
export default function NoAccess({ email, turnedOff }: { email: string; turnedOff: boolean }) {
  return (
    <div className="flex min-h-dvh items-center justify-center p-4">
      <div className="card w-full max-w-md p-7 text-center">
        <LogoMark className="mx-auto h-10 w-10" />
        <h1 className="mt-4 font-display text-3xl font-bold">
          <T>{turnedOff ? "This account is turned off" : "Waiting for access"}</T>
        </h1>
        <p className="mt-3 text-lead">
          <T>{turnedOff
            ? "The shop owner has turned off this login. Ask the owner if you think this is a mistake."
            : "You are signed in, but the shop owner has not given this login a role yet. Ask the owner to open Team and set one up for you."}</T>
        </p>
        <p className="mt-3 truncate text-sm text-lead" title={email}><T p={{ email: email }}>{"Signed in as {email}"}</T></p>
        <div className="mt-6">
          <SignOutButton />
        </div>
      </div>
    </div>
  );
}
