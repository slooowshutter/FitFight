import { Avatar, AvatarFallback, AvatarImage } from "@/components/ui/avatar";
import type { MediaObject } from "@/lib/types/media/media";

/** Same picture as the app: the chosen animal, a custom animal's art, else the photo, else initials. */
export function PersonAvatar({
    person,
    size,
    className,
}: {
    person: {
        display_name: string;
        handle: string;
        avatar: MediaObject | null;
        companion_id: string | null;
        companion_image_url?: string | null;
    };
    size?: "sm" | "default" | "lg";
    className?: string;
}) {
    const src =
        person.companion_id === "custom"
            ? (person.companion_image_url ?? person.avatar?.url)
            : person.companion_id
              ? `/landing/companion-${person.companion_id}-avatar.webp`
              : person.avatar?.url;
    return (
        <Avatar size={size} className={className}>
            {src ? <AvatarImage src={src} alt="" /> : null}
            <AvatarFallback>
                {(person.display_name || person.handle)
                    .slice(0, 1)
                    .toUpperCase()}
            </AvatarFallback>
        </Avatar>
    );
}
