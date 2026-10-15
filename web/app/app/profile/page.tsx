"use client";

import { ProfileView } from "@/components/web-app/profile-view";
import { useMe } from "@/components/web-app/web-app-shell";

export default function ProfilePage() {
    const me = useMe();
    return <ProfileView userID={me.user_id} />;
}
