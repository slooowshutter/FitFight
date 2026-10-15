"use client";

import type { Session } from "@supabase/supabase-js";
import {
    ActivityIcon,
    LayoutDashboardIcon,
    LogOutIcon,
    MessageSquareIcon,
    PlusIcon,
    SwordsIcon,
    UserIcon,
} from "lucide-react";
import Link from "next/link";
import { usePathname } from "next/navigation";
import {
    createContext,
    useContext,
    useEffect,
    useState,
    type ReactNode,
} from "react";
import { SignInButtons } from "@/components/sign-in-buttons";
import { Alert, AlertDescription, AlertTitle } from "@/components/ui/alert";
import { Button } from "@/components/ui/button";
import {
    Card,
    CardContent,
    CardDescription,
    CardFooter,
    CardHeader,
    CardTitle,
} from "@/components/ui/card";
import {
    DropdownMenu,
    DropdownMenuContent,
    DropdownMenuGroup,
    DropdownMenuItem,
    DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import {
    Sidebar,
    SidebarContent,
    SidebarFooter,
    SidebarGroup,
    SidebarGroupContent,
    SidebarHeader,
    SidebarInset,
    SidebarMenu,
    SidebarMenuButton,
    SidebarMenuItem,
    SidebarProvider,
    SidebarTrigger,
} from "@/components/ui/sidebar";
import { Spinner } from "@/components/ui/spinner";
import { PersonAvatar } from "@/components/web-app/person-avatar";
import { FitFightApiError, useFitFightApi } from "@/hooks/use-fitfight-api";
import {
    browserProjectURL,
    browserSupabase,
    signOut,
} from "@/lib/supabase/browser-client";
import { devSignInResponseSchema } from "@/lib/types/auth/dev-sign-in";
import { profileSchema, type Profile } from "@/lib/types/profiles/profile";

const MeContext = createContext<{ me: Profile; reload: () => void } | null>(
    null,
);

/** The signed-in person's profile. Every web app screen renders inside the shell, so it is always there. */
export function useMe(): Profile {
    const context = useContext(MeContext);
    if (!context) throw new Error("useMe outside WebAppShell");
    return context.me;
}

/** Refetches the profile the sidebar and every screen show, after the person edits it. */
export function useReloadMe(): () => void {
    const context = useContext(MeContext);
    if (!context) throw new Error("useReloadMe outside WebAppShell");
    return context.reload;
}

const tabs = [
    { href: "/app", label: "Fights", icon: SwordsIcon },
    { href: "/app/new", label: "New fight", icon: PlusIcon },
    { href: "/app/feed", label: "Feed", icon: ActivityIcon },
    { href: "/app/feedback", label: "Feedback", icon: MessageSquareIcon },
    { href: "/app/profile", label: "Profile", icon: UserIcon },
];
// The iPhone app's admin usernames (SessionStore.adminHandles). The dashboard API checks the real admin itself.
const adminHandles = ["marc", "rad"];

export function WebAppShell({ children }: { children: ReactNode }) {
    const [session, setSession] = useState<Session | null | undefined>(
        undefined,
    );
    const [failed, setFailed] = useState(false);
    const [working, setWorking] = useState(false);
    const me = useFitFightApi(session ? "me" : null, profileSchema);
    const pathname = usePathname();

    useEffect(() => {
        browserSupabase.auth.getSession().then(async ({ data }) => {
            // NOTE: `next dev` only (this branch is removed from production builds): sign in as DEV_AUTOLOGIN_EMAIL on
            // first load. After signing out, the next reload signs back in; remove the variable to stay signed out.
            if (!data.session && process.env.NODE_ENV === "development") {
                const response = await fetch("/api/v1/dev/sign-in", {
                    method: "POST",
                });
                if (response.ok) {
                    await browserSupabase.auth.verifyOtp({
                        type: "email",
                        token_hash: devSignInResponseSchema.parse(
                            await response.json(),
                        ).token_hash,
                    });
                }
            }
            setSession((await browserSupabase.auth.getSession()).data.session);
        });
        const { data } = browserSupabase.auth.onAuthStateChange(
            (_event, next) => setSession(next),
        );
        return () => data.subscription.unsubscribe();
    }, []);

    if (session === undefined || (session && !me.data && !me.error)) {
        return (
            <div className="flex min-h-svh items-center justify-center">
                <Spinner />
            </div>
        );
    }

    if (!session) {
        return (
            <div className="flex min-h-svh items-center justify-center p-6">
                <Card className="w-full max-w-sm">
                    <CardHeader>
                        <CardTitle className="text-2xl font-extrabold">
                            Sign in to FitFight
                        </CardTitle>
                        <CardDescription>
                            Use the same Apple or Google account as in the app.
                            Your Fights, Feed and Profile are all here.
                        </CardDescription>
                    </CardHeader>
                    <CardContent className="flex flex-col gap-3">
                        <SignInButtons
                            supabase={browserSupabase}
                            projectURL={browserProjectURL}
                            locale="en_US"
                            hidden={working}
                            className="flex flex-col gap-3 [&_#appleid-signin]:h-10 [&_#appleid-signin]:w-[300px] [&_#appleid-signin]:cursor-pointer"
                            onStart={() => {
                                setWorking(true);
                                setFailed(false);
                            }}
                            onSignedIn={async () => setWorking(false)}
                            onFailed={() => {
                                setWorking(false);
                                setFailed(true);
                            }}
                        />
                        {working ? <Spinner /> : null}
                        {failed ? (
                            <Alert variant="destructive">
                                <AlertTitle>Sign-in did not work</AlertTitle>
                                <AlertDescription>Try again.</AlertDescription>
                            </Alert>
                        ) : null}
                    </CardContent>
                </Card>
            </div>
        );
    }

    if (!me.data) {
        const missing =
            me.error instanceof FitFightApiError &&
            me.error.code === "profile_missing";
        return (
            <div className="flex min-h-svh items-center justify-center p-6">
                <Card className="w-full max-w-sm">
                    <CardHeader>
                        <CardTitle>
                            {missing
                                ? "Finish signing up in the app"
                                : "Something went wrong"}
                        </CardTitle>
                        <CardDescription>
                            {missing
                                ? "This account has no FitFight username yet. Open the iPhone app, sign in with the same account and pick a username, then come back."
                                : me.error?.message}
                        </CardDescription>
                    </CardHeader>
                    <CardFooter className="gap-2">
                        <Button variant="outline" onClick={signOut}>
                            Sign out
                        </Button>
                        <Button onClick={me.reload}>Try again</Button>
                    </CardFooter>
                </Card>
            </div>
        );
    }

    return (
        <MeContext.Provider value={{ me: me.data, reload: me.reload }}>
            <SidebarProvider>
                <Sidebar collapsible="icon">
                    <SidebarHeader>
                        <SidebarMenu>
                            <SidebarMenuItem>
                                <SidebarMenuButton size="lg" asChild>
                                    <a href="/">
                                        <span className="flex size-8 items-center justify-center rounded-lg bg-primary text-sm font-extrabold text-primary-foreground">
                                            FF
                                        </span>
                                        <span className="text-base font-extrabold">
                                            FitFight
                                        </span>
                                    </a>
                                </SidebarMenuButton>
                            </SidebarMenuItem>
                        </SidebarMenu>
                    </SidebarHeader>
                    <SidebarContent>
                        <SidebarGroup>
                            <SidebarGroupContent>
                                <SidebarMenu>
                                    {[
                                        ...tabs,
                                        ...(adminHandles.includes(
                                            me.data.handle.toLowerCase(),
                                        )
                                            ? [
                                                  {
                                                      href: "/app/admin",
                                                      label: "Admin",
                                                      icon: LayoutDashboardIcon,
                                                  },
                                              ]
                                            : []),
                                    ].map((tab) => (
                                        <SidebarMenuItem key={tab.href}>
                                            <SidebarMenuButton
                                                asChild
                                                tooltip={tab.label}
                                                isActive={
                                                    tab.href === "/app"
                                                        ? pathname === "/app" ||
                                                          pathname.startsWith(
                                                              "/app/fights",
                                                          )
                                                        : pathname ===
                                                              tab.href ||
                                                          pathname.startsWith(
                                                              `${tab.href}/`,
                                                          )
                                                }
                                            >
                                                <Link href={tab.href}>
                                                    <tab.icon />
                                                    <span>{tab.label}</span>
                                                </Link>
                                            </SidebarMenuButton>
                                        </SidebarMenuItem>
                                    ))}
                                </SidebarMenu>
                            </SidebarGroupContent>
                        </SidebarGroup>
                    </SidebarContent>
                    <SidebarFooter>
                        <SidebarMenu>
                            <SidebarMenuItem>
                                <DropdownMenu>
                                    <DropdownMenuTrigger asChild>
                                        <SidebarMenuButton size="lg">
                                            <PersonAvatar person={me.data} />
                                            <span className="flex min-w-0 flex-col">
                                                <span className="truncate font-bold">
                                                    {me.data.display_name}
                                                </span>
                                                <span className="truncate text-xs text-muted-foreground">
                                                    @{me.data.handle}
                                                </span>
                                            </span>
                                        </SidebarMenuButton>
                                    </DropdownMenuTrigger>
                                    <DropdownMenuContent
                                        side="top"
                                        align="start"
                                    >
                                        <DropdownMenuGroup>
                                            <DropdownMenuItem
                                                onSelect={signOut}
                                            >
                                                <LogOutIcon />
                                                Sign out
                                            </DropdownMenuItem>
                                        </DropdownMenuGroup>
                                    </DropdownMenuContent>
                                </DropdownMenu>
                            </SidebarMenuItem>
                        </SidebarMenu>
                    </SidebarFooter>
                </Sidebar>
                <SidebarInset>
                    <header className="flex h-14 items-center gap-2 border-b px-4 md:hidden">
                        <SidebarTrigger />
                        <span className="font-extrabold">FitFight</span>
                    </header>
                    <div className="mx-auto flex w-full max-w-6xl flex-col gap-6 p-4 md:p-8">
                        {children}
                    </div>
                </SidebarInset>
            </SidebarProvider>
        </MeContext.Provider>
    );
}
