import type { SiteLanguage } from "@/lib/types/marketing/site-language";

// Sample people, fights and posts for the phone mockups. Every number is fictional.
const en = {
    nav: {
        how: "How it works",
        companions: "Companions",
        pricing: "Pricing",
        faq: "FAQ",
    },
    homeLabel: "FitFight home",
    getApp: "Get the app",
    download: "Download on the App Store",
    hero: {
        eyebrow: "Step challenges with friends",
        title: "Let friendly competition",
        titleAccent: "move you.",
        lede: "Join or start a challenge, let Apple Health keep score, and find out who really walks the most.",
        tryIt: "Try it",
        meta: ["Free", "iPhone", "Apple Health", "WHOOP"],
        betaMeta: [
            "iPhone",
            "Tap the TestFlight link twice",
            "Apple Health",
            "WHOOP",
        ],
        hint: "Tap the tabs. This is the real app.",
    },
    totalSteps: {
        eyebrow: "Steps recorded",
        caption: "since people joined FitFight",
    },
    what: {
        eyebrow: "What it is",
        statement: [
            "FitFight is a step challenge between ",
            "you",
            " and ",
            "your friends",
            ". Choose a length, set the stakes, then start walking.",
        ],
        facts: ["Steps only", "Private by default", "Free, no ads"],
        frags: [
            ["Every fight at a glance", "Ahead in green, behind in orange."],
            ["Live standings", "Apple Health totals, updated as you walk."],
            [
                "A Feed for every fight",
                "Photos, posts and very serious trash talk.",
            ],
        ],
    },
    fights: [
        {
            name: "Walk Wars",
            left: "1 day and 7 hours left",
            gap: "+860",
            ahead: true,
            rival: "capybara",
        },
        {
            name: "Roommate Rumble",
            left: "5 days left",
            gap: "−1,260",
            ahead: false,
            rival: "panda",
        },
        {
            name: "Step it Up",
            left: "2 days left",
            gap: "+2,840",
            ahead: true,
            rival: "silverback",
        },
        {
            name: "Office Showdown",
            left: "4 days left",
            gap: "−430",
            ahead: false,
            rival: "hedgehog",
        },
    ],
    standings: [
        { name: "You", animal: "tiger", seen: "5 minutes ago", total: "61.2K" },
        {
            name: "Leo",
            animal: "silverback",
            seen: "12 minutes ago",
            total: "58.4K",
        },
        {
            name: "Nina",
            animal: "capybara",
            seen: "1 hour ago",
            total: "54.9K",
        },
    ],
    posts: [
        {
            who: "Leo",
            animal: "silverback",
            ago: "12m",
            fight: "Step it Up",
            text: "Nine floors of stairs at lunch. Enjoy the lead while it lasts.",
            reacts: ["🔥 4", "😂 2"],
            comments: "3 comments",
        },
        {
            who: "Nina",
            animal: "capybara",
            ago: "1h",
            fight: "Walk Wars",
            text: "Sunday loop done. 14,210 steps and zero regrets.",
            reacts: ["👏 5"],
            comments: "1 comment",
        },
        {
            who: "Sam",
            animal: "hedgehog",
            ago: "3h",
            fight: "",
            text: "Walked to the bakery. Walked back. Ate the evidence.",
            reacts: ["😂 6", "🥐 3"],
            comments: "2 comments",
        },
    ],
    goal: {
        eyebrow: "The goal",
        lines: [
            "Walk the long way.",
            "Take the stairs.",
            "Get off one stop early.",
        ],
        win: "Win the challenge.",
        gaps: [
            ["Step it Up", "+2,840", "steps ahead", "Relax. Or don’t."],
            [
                "Roommate Rumble",
                "−1,260",
                "steps behind",
                "Time for the long way home.",
            ],
        ],
        nextPose: "Next pose:",
        nextPoseName: "Pushing",
        toGo: "1,568 steps to go",
        poseNote:
            "Your companion stands taller at 3k, 6k, 10k and 15k steps a day.",
        note: "The goal is not a perfect 10,000. It is a little further than yesterday, because someone you like is walking too.",
    },
    how: {
        eyebrow: "How it works",
        title: "Three steps to start.",
        titleAccent: "One winner",
        titleEnd: "to finish.",
        steps: [
            [
                "Start or join a fight",
                "Pick how long it lasts, type what the loser has to do or what the champion receives, and share the link with others.",
            ],
            [
                "Move to win",
                "Apple Health keeps the score while you live your day. The standings update as you walk.",
            ],
            [
                "Claim the win",
                "When time is up, the highest total wins. The loser does what you agreed.",
            ],
        ],
    },
    composer: {
        back: "Back",
        stepOf: (step: number) => `Step ${step} of 5`,
        metricTitle: "What are you competing on?",
        metricText:
            "Every fight tracks one metric. Steps is the only metric available right now.",
        steps: "Steps",
        stepsDetail: "Highest total wins · Apple Health",
        lengthTitle: "How long will the fight last?",
        lengthText:
            "It starts immediately. Steps after the exact end time do not count.",
        duration: "Duration",
        lengths: ["3 days", "1 week", "2 weeks", "1 month"],
        custom: "Custom",
        repeat: "Repeat when it ends",
        repeatDetail: "The next window starts when this one ends",
        repeats: " · repeats",
        joinTitle: "Who can join?",
        joinPrivate:
            "New fights start private. People still join with the code or invite link. Usernames are optional.",
        joinPublic:
            "Listed on Join. Anyone with the code or invite link can join. Usernames are optional.",
        private: "Private",
        privateDetail: "Default · code or invite link",
        public: "Public",
        publicDetail: "Listed on Join",
        username: "Username",
        usernamePlaceholder: "@username",
        add: "Add",
        titleTitle: "Title and action",
        titleText: "Give the fight a title. The loser action is optional.",
        title: "Title",
        titlePlaceholder: "Weekend walk-off",
        action: "Loser action",
        actionPlaceholder: "Cook dinner",
        defaultTitle: "Step it Up",
        defaultAction: "Buy the croissants",
        reviewTitle: "Ready to fight?",
        reviewText: "Check the agreement before you start.",
        metric: "Metric",
        metricValue: "Steps · highest total wins",
        privateValue: "Join with code or invite link",
        none: "None",
        health: "Apple Health Steps",
        connected: "Connected",
        versus: "You vs @leo, @nina, @sam.",
        winner: (length: string) => `The most Steps after ${length} wins.`,
        loserWill: (action: string) => `The loser will ${action}.`,
        next: "Next",
        start: "Start fight",
        doneTitle: "Fight on.",
        doneText: (title: string) =>
            `Share the link so your friends can join ${title}.`,
        share: "Share invite",
        restart: "Start over",
    },
    companions: {
        eyebrow: "Companions",
        title: "Pick a companion.",
        titleAccent: "Watch it grow.",
        lede: "Your companion stands in for you in fights, standings and the Feed. It changes pose as your steps add up during the day. Change it any time, unlock a Special, or describe any animal and get your own.",
        pick: "Pick your animal",
        walk: "Walk. It changes pose with your steps today.",
        stepsToday: "Steps today",
        poses: ["Resting", "Heading out", "On the move", "Pushing", "Peak"],
        ranges: ["Under 3k", "3k+", "6k+", "10k+", "15k+"],
        animals: [
            { id: "tiger", name: "Tiger", caption: "Wraps on. Excuses off." },
            {
                id: "black-panther",
                name: "Black Panther",
                caption: "Doesn’t count steps. Steps count him.",
            },
            {
                id: "lone-wolf",
                name: "Lone Wolf",
                caption: "Runs alone. Finishes first.",
            },
            {
                id: "snow-leopard",
                name: "Snow Leopard",
                caption: "Cold start. Hot finish.",
            },
            {
                id: "night-owl",
                name: "Night Owl",
                caption: "Up at 3 a.m. Still ahead of you.",
            },
            {
                id: "crocodile",
                name: "Crocodile",
                caption: "Smiles at the finish line. Bad sign.",
            },
            {
                id: "peacock",
                name: "Peacock",
                caption: "Dressed to win. Also wins.",
            },
            {
                id: "flamingo",
                name: "Flamingo",
                caption: "Stands on one leg. Still out-walks you.",
            },
            {
                id: "persian-cat",
                name: "Persian Cat",
                caption: "Pearls on. Pinky up. Pace up.",
            },
            {
                id: "ostrich",
                name: "Ostrich",
                caption: "Never buries her head. Only the competition.",
            },
            {
                id: "cheetah",
                name: "Cheetah",
                caption: "Fashionably fast. Never fashionably late.",
            },
            {
                id: "bald-eagle",
                name: "Bald Eagle",
                caption: "Spotted your step count from up here.",
            },
            {
                id: "silverback",
                name: "Silverback",
                caption: "Skips nothing. Especially not leg day.",
            },
            {
                id: "kangaroo",
                name: "Kangaroo",
                caption: "Counts jumps as steps. Nobody argues.",
            },
            {
                id: "bull",
                name: "Bull",
                caption: "Charges first. Asks questions never.",
            },
            {
                id: "moose",
                name: "Moose",
                caption: "Coach says one more lap. Coach is me.",
            },
            {
                id: "bison",
                name: "Bison",
                caption: "Skipping rope. Never skipping cardio.",
            },
            {
                id: "camel",
                name: "Camel",
                caption: "Hydrated in 2019. Still going.",
            },
            {
                id: "panda",
                name: "Panda",
                caption: "Bubble tea first. Then domination.",
            },
            {
                id: "capybara",
                name: "Capybara",
                caption: "Unbothered. Undefeated.",
            },
            {
                id: "hedgehog",
                name: "Hedgehog",
                caption: "Prickly before coffee. Fast after.",
            },
            {
                id: "ginger-cat",
                name: "Ginger Cat",
                caption: "Woke up at noon. Won by dinner.",
            },
            {
                id: "alpaca",
                name: "Alpaca",
                caption: "Spits on rest days only.",
            },
            {
                id: "seal",
                name: "Seal",
                caption: "Warm flippers. Cold competition.",
            },
            {
                id: "hamster",
                name: "Hamster",
                caption: "Small legs. Unreasonable cardio.",
            },
            {
                id: "tree-frog",
                name: "Tree Frog",
                caption: "Hops count double. Allegedly.",
            },
            {
                id: "mouse",
                name: "Mouse",
                caption: "Small steps. So many of them.",
            },
            {
                id: "guinea-pig",
                name: "Guinea Pig",
                caption: "Squeaks politely. Walks relentlessly.",
            },
            {
                id: "duck",
                name: "Duck",
                caption: "Small duck. Big lift. Bigger quack.",
            },
            {
                id: "donkey",
                name: "Donkey",
                caption: "Stubborn about cardio. In a good way.",
            },
        ],
    },
    options: {
        eyebrow: "Fight options",
        title: "Set it up",
        titleAccent: "your way.",
        items: [
            ["Metric", "Steps. The highest total wins."],
            [
                "Duration",
                "3 days, 1 week, 2 weeks, 1 month, or your own dates.",
            ],
            ["Repeat", "Start the next round on its own when one ends."],
            [
                "Who can join",
                "Private by default. Go public to be listed on Join.",
            ],
            ["Invite", "A link or a 4-character code. Usernames are optional."],
            ["Loser action", "Anything you agree on. It stays on the fight."],
            ["Feed", "Photos, videos, posts and reactions for each fight."],
            ["Reminders", "Optional nudges while a fight is on."],
        ],
    },
    pricing: {
        eyebrow: "Pricing",
        tag: "Everything included",
        free: "Free",
        text: "Every fight, every feature and all 12 companions. No ads. No tracking.",
        included: [
            "Unlimited fights",
            "Live standings and charts",
            "All 12 companions",
            "Feed, posts and reactions",
            "Apple Health and WHOOP sync",
        ],
        later: "Optional extras",
        extras: [
            [
                "Special",
                "€0.99",
                "Buy any special companion once and keep it forever. Collect as many as you like.",
            ],
            [
                "Make it yours",
                "€2.99",
                "Describe any animal and get a custom companion in five poses. Invite a friend to FitFight, and you each get one free.",
            ],
        ],
    },
    faq: {
        eyebrow: "FAQ",
        title: "Questions, answered.",
        note: "Can’t find yours? Ask in the Feedback tab of the app.",
        search: "Search questions",
        noMatch:
            "No match. Ask in the Feedback tab, where people vote on the best ideas.",
        items: [
            [
                "What is FitFight?",
                "A free iPhone app for step challenges with friends. Start a fight, everyone walks, and Apple Health keeps the score. The highest total wins.",
            ],
            [
                "How are my steps counted?",
                "FitFight reads Steps from Apple Health, the same total you see in the Health app. Apple merges iPhone and Apple Watch steps, so nothing counts twice.",
            ],
            [
                "Do my friends need the app?",
                "Yes. Everyone in a fight needs FitFight on an iPhone. Send them the link or the code and they join in a tap.",
            ],
            [
                "How long does a fight last?",
                "You pick: 3 days, 1 week, 2 weeks or 1 month, or your own dates. The fight ends on its own and the highest total wins.",
            ],
            [
                "What does the loser do?",
                "Whatever you agree on. Type it when you start the fight, like “Buy the croissants”. It stays on the fight, so nobody forgets.",
            ],
            [
                "Who can see my steps?",
                "The people in your fight see your total, your daily steps in the fight chart and your rank. Nobody gets your raw Apple Health data.",
            ],
            [
                "What is a companion?",
                "An illustrated animal that stands in for you in fights, standings and the Feed. Pick one of 12. It changes pose as your steps add up during the day.",
            ],
            [
                "How much does it cost?",
                "Nothing. FitFight is free, with no ads. Specials and custom companions are optional purchases.",
            ],
            [
                "Does it work with WHOOP?",
                "Yes. In the app, open Profile, then Settings, then Connectors, and connect WHOOP. FitFight gets your sleep, recovery, strain and workouts, updated every hour. Fight steps still come from Apple Health, so turn on Apple Health in the WHOOP app to count your WHOOP steps.",
            ],
            [
                "Is there an Android app?",
                "Not right now. FitFight counts steps with Apple Health, so it is iPhone only.",
            ],
        ],
    },
    end: {
        title: "Your friends are already walking.",
        text: "Start a fight tonight. Settle it by Sunday.",
        art: "Rabbit, Turtle, Fox and Badger jogging on a trail",
    },
    footer: {
        tagline: "Challenge friends. Move to win.",
        privacy: ["Privacy", "/privacy"],
        support: ["Support", "/support"],
        otherLanguage: ["Français", "/?lang=fr", "fr"],
    },
    phone: {
        tabs: ["Fights", "New", "Feed", "Feedback", "Profile"],
        fightsTitle: "Fights",
        leading: "Leading 2 of 4",
        stepsToday: "steps today",
        challenges: "Challenges",
        segments: ["Current", "Invited 1", "Past"],
        ahead: "steps ahead",
        behind: "steps behind",
        newTitle: "New fight",
        newRule: "Steps. Highest total wins.",
        createOrJoin: "Create or join?",
        createOrJoinText:
            "Start a new fight, or join one that’s already going.",
        create: "Create",
        createText: "Start a new fight",
        join: "Join",
        joinText: "Code, invite link, or a public fight",
        feedTitle: "Feed",
        public: "Public",
        feedbackTitle: "Feedback",
        feedbackSegments: ["Top", "Features", "Bugs"],
        requests: [
            ["Weekly recap on Sunday night", "Feature", "42"],
            ["Today’s steps widget", "Feature", "31"],
            ["Show who walked the most today", "Feature", "24"],
            ["Chart labels overlap on small phones", "Bug", "9"],
        ],
        newRequest: "New request",
        copyUsername: "Copy username",
        changeAnimal: "Change animal",
        healthEyebrow: "Apple Health",
        healthRow: "Apple Health Steps",
        connected: "Connected",
        on: "On",
        settingsEyebrow: "Settings",
        settings: [
            "Refer a friend",
            "Preferences",
            "Privacy",
            "Support",
            "Versions",
        ],
    },
};

const fr: typeof en = {
    nav: {
        how: "Comment ça marche",
        companions: "Compagnons",
        pricing: "Prix",
        faq: "FAQ",
    },
    homeLabel: "Accueil FitFight",
    getApp: "Obtenir l’app",
    download: "Télécharger dans l’App Store",
    hero: {
        eyebrow: "Défis de pas entre amis",
        title: "Bougez plus grâce aux défis",
        titleAccent: "entre amis.",
        lede: "Rejoignez ou lancez un défi, laissez Santé d’Apple compter les pas et découvrez qui marche vraiment le plus.",
        tryIt: "Essayer",
        meta: ["Gratuit", "iPhone", "Santé d’Apple", "WHOOP"],
        betaMeta: [
            "iPhone",
            "Ouvrez le lien TestFlight deux fois",
            "Santé d’Apple",
            "WHOOP",
        ],
        hint: "Touchez les onglets. C’est la vraie app.",
    },
    totalSteps: {
        eyebrow: "Pas enregistrés",
        caption: "depuis que chacun a rejoint FitFight",
    },
    what: {
        eyebrow: "Le principe",
        statement: [
            "FitFight est un défi de pas entre ",
            "vous",
            " et ",
            "vos amis",
            ". Choisissez une durée, fixez l’enjeu, puis mettez-vous en marche.",
        ],
        facts: ["Seulement les pas", "Privé par défaut", "Gratuit, sans pub"],
        frags: [
            [
                "Tous vos défis d’un coup d’œil",
                "En avance en vert, en retard en orange.",
            ],
            [
                "Classement en direct",
                "Les totaux de Santé d’Apple, mis à jour pendant que vous marchez.",
            ],
            [
                "Un fil pour chaque défi",
                "Photos, messages et chambrage très sérieux.",
            ],
        ],
    },
    fights: [
        {
            name: "La guerre des pas",
            left: "Encore 1 jour et 7 heures",
            gap: "+860",
            ahead: true,
            rival: "capybara",
        },
        {
            name: "Duel de colocs",
            left: "Encore 5 jours",
            gap: "−1 260",
            ahead: false,
            rival: "panda",
        },
        {
            name: "Accélère le pas",
            left: "Encore 2 jours",
            gap: "+2 840",
            ahead: true,
            rival: "silverback",
        },
        {
            name: "Le match du bureau",
            left: "Encore 4 jours",
            gap: "−430",
            ahead: false,
            rival: "hedgehog",
        },
    ],
    standings: [
        {
            name: "Vous",
            animal: "tiger",
            seen: "il y a 5 minutes",
            total: "61,2 k",
        },
        {
            name: "Leo",
            animal: "silverback",
            seen: "il y a 12 minutes",
            total: "58,4 k",
        },
        {
            name: "Nina",
            animal: "capybara",
            seen: "il y a 1 heure",
            total: "54,9 k",
        },
    ],
    posts: [
        {
            who: "Leo",
            animal: "silverback",
            ago: "12 min",
            fight: "Accélère le pas",
            text: "Neuf étages d’escaliers à midi. Profitez de votre avance tant qu’elle dure.",
            reacts: ["🔥 4", "😂 2"],
            comments: "3 commentaires",
        },
        {
            who: "Nina",
            animal: "capybara",
            ago: "1 h",
            fight: "La guerre des pas",
            text: "Boucle du dimanche bouclée. 14 210 pas et zéro regret.",
            reacts: ["👏 5"],
            comments: "1 commentaire",
        },
        {
            who: "Sam",
            animal: "hedgehog",
            ago: "3 h",
            fight: "",
            text: "Marché jusqu’à la boulangerie. Marché au retour. Mangé les preuves.",
            reacts: ["😂 6", "🥐 3"],
            comments: "2 commentaires",
        },
    ],
    goal: {
        eyebrow: "L’objectif",
        lines: [
            "Rallongez le trajet.",
            "Prenez l’escalier.",
            "Descendez un arrêt plus tôt.",
        ],
        win: "Gagnez le défi.",
        gaps: [
            [
                "Accélère le pas",
                "+2 840",
                "pas d’avance",
                "Détendez-vous. Ou pas.",
            ],
            [
                "Duel de colocs",
                "−1 260",
                "pas de retard",
                "C’est l’heure du chemin le plus long.",
            ],
        ],
        nextPose: "Prochaine pose :",
        nextPoseName: "À fond",
        toGo: "Encore 1 568 pas",
        poseNote:
            "Votre compagnon se redresse à 3 000, 6 000, 10 000 et 15 000 pas par jour.",
        note: "Le but n’est pas un 10 000 parfait. C’est un peu plus loin qu’hier, parce que quelqu’un que vous aimez marche aussi.",
    },
    how: {
        eyebrow: "Comment ça marche",
        title: "Trois étapes pour se lancer.",
        titleAccent: "Un seul gagnant",
        titleEnd: "à l’arrivée.",
        steps: [
            [
                "Lancez ou rejoignez un défi",
                "Choisissez sa durée, écrivez le gage du perdant ou ce que remporte le champion, et partagez le lien avec les autres.",
            ],
            [
                "Bougez pour gagner",
                "Santé d’Apple compte les pas pendant que vous vivez votre journée. Le classement se met à jour à chaque pas.",
            ],
            [
                "Décrochez la victoire",
                "À la fin, le total le plus élevé gagne. Le perdant fait le gage convenu.",
            ],
        ],
    },
    composer: {
        back: "Retour",
        stepOf: (step: number) => `Étape ${step} sur 5`,
        metricTitle: "Sur quoi porte le défi ?",
        metricText:
            "Chaque défi suit une mesure. Les pas sont la seule mesure disponible pour le moment.",
        steps: "Pas",
        stepsDetail: "Le total le plus élevé gagne · Santé d’Apple",
        lengthTitle: "Combien de temps durera le défi ?",
        lengthText:
            "Il commence immédiatement. Les pas effectués après l’heure exacte de fin ne comptent pas.",
        duration: "Durée",
        lengths: ["3 jours", "1 semaine", "2 semaines", "1 mois"],
        custom: "Personnalisé",
        repeat: "Recommencer à la fin",
        repeatDetail: "La fenêtre suivante commence à la fin de celle-ci",
        repeats: " · recommence",
        joinTitle: "Qui peut rejoindre ?",
        joinPrivate:
            "Les nouveaux défis commencent privés. On peut quand même rejoindre avec le code ou le lien d’invitation. Les noms d’utilisateur sont facultatifs.",
        joinPublic:
            "Listé dans Rejoindre. Toute personne avec le code ou le lien d’invitation peut rejoindre. Les noms d’utilisateur sont facultatifs.",
        private: "Privé",
        privateDetail: "Par défaut · code ou lien d’invitation",
        public: "Public",
        publicDetail: "Listé dans Rejoindre",
        username: "Nom d’utilisateur",
        usernamePlaceholder: "@nom_utilisateur",
        add: "Ajouter",
        titleTitle: "Titre et gage",
        titleText: "Donnez un titre au défi. Le gage est facultatif.",
        title: "Titre",
        titlePlaceholder: "Défi du week-end",
        action: "Gage du perdant",
        actionPlaceholder: "Préparer le dîner",
        defaultTitle: "Accélère le pas",
        defaultAction: "Acheter les croissants",
        reviewTitle: "Prêt pour le défi ?",
        reviewText: "Vérifiez l’accord avant de lancer.",
        metric: "Mesure",
        metricValue: "Pas · le total le plus élevé gagne",
        privateValue: "Rejoindre avec le code ou le lien d’invitation",
        none: "Aucun",
        health: "Pas de Santé d’Apple",
        connected: "Connecté",
        versus: "Vous contre @leo, @nina, @sam.",
        winner: (length: string) =>
            `Le plus grand nombre de pas gagne après ${length}.`,
        loserWill: (action: string) => `Le perdant devra : ${action}.`,
        next: "Suivant",
        start: "Lancer le défi",
        doneTitle: "C’est parti.",
        doneText: (title: string) =>
            `Partagez le lien pour que vos amis rejoignent ${title}.`,
        share: "Partager l’invitation",
        restart: "Recommencer",
    },
    companions: {
        eyebrow: "Compagnons",
        title: "Choisissez un compagnon.",
        titleAccent: "Regardez-le grandir.",
        lede: "Votre compagnon vous représente dans les défis, le classement et le fil. Il change de pose à mesure que vos pas s’accumulent dans la journée. Changez-en quand vous voulez, débloquez un Spécial ou décrivez n’importe quel animal pour avoir le vôtre.",
        pick: "Choisissez votre animal",
        walk: "Marchez. Il change de pose avec vos pas du jour.",
        stepsToday: "Pas aujourd’hui",
        poses: ["Au repos", "En route", "En marche", "À fond", "Au sommet"],
        ranges: [
            "Moins de 3\u00a0k",
            "3\u00a0k+",
            "6\u00a0k+",
            "10\u00a0k+",
            "15\u00a0k+",
        ],
        animals: [
            {
                id: "tiger",
                name: "Tigre",
                caption: "Bandages mis. Excuses au placard.",
            },
            {
                id: "black-panther",
                name: "Panthère noire",
                caption: "Ne compte pas ses pas. Ses pas le comptent.",
            },
            {
                id: "lone-wolf",
                name: "Loup solitaire",
                caption: "Court seul. Finit premier.",
            },
            {
                id: "snow-leopard",
                name: "Léopard des neiges",
                caption: "Départ à froid. Arrivée brûlante.",
            },
            {
                id: "night-owl",
                name: "Oiseau de nuit",
                caption: "Debout à 3 h du matin. Toujours devant vous.",
            },
            {
                id: "crocodile",
                name: "Crocodile",
                caption: "Sourit à l’arrivée. Mauvais signe.",
            },
            {
                id: "peacock",
                name: "Paon",
                caption: "Habillé pour gagner. Et il gagne.",
            },
            {
                id: "flamingo",
                name: "Flamant rose",
                caption:
                    "Tient sur une patte. Marche quand même plus que vous.",
            },
            {
                id: "persian-cat",
                name: "Chat persan",
                caption: "Perles au cou. Petit doigt levé. Allure en hausse.",
            },
            {
                id: "ostrich",
                name: "Autruche",
                caption:
                    "Ne se cache jamais la tête. Elle enterre la concurrence.",
            },
            {
                id: "cheetah",
                name: "Guépard",
                caption: "Rapide avec élégance. En retard, jamais.",
            },
            {
                id: "bald-eagle",
                name: "Aigle à tête blanche",
                caption: "A repéré votre nombre de pas de là-haut.",
            },
            {
                id: "silverback",
                name: "Dos argenté",
                caption: "Ne saute rien. Surtout pas la séance jambes.",
            },
            {
                id: "kangaroo",
                name: "Kangourou",
                caption: "Compte ses sauts comme des pas. Personne ne discute.",
            },
            {
                id: "bull",
                name: "Taureau",
                caption: "Fonce d’abord. Ne pose jamais de questions.",
            },
            {
                id: "moose",
                name: "Élan",
                caption: "Le coach dit encore un tour. Le coach, c’est moi.",
            },
            {
                id: "bison",
                name: "Bison",
                caption: "Saute à la corde. Ne saute jamais le cardio.",
            },
            {
                id: "camel",
                name: "Chameau",
                caption: "Hydraté en 2019. Toujours en route.",
            },
            {
                id: "panda",
                name: "Panda",
                caption: "Bubble tea d’abord. Domination ensuite.",
            },
            {
                id: "capybara",
                name: "Capybara",
                caption: "Imperturbable. Invaincu.",
            },
            {
                id: "hedgehog",
                name: "Hérisson",
                caption: "Piquant avant le café. Rapide après.",
            },
            {
                id: "ginger-cat",
                name: "Chat roux",
                caption: "Réveillé à midi. Vainqueur avant le dîner.",
            },
            {
                id: "alpaca",
                name: "Alpaga",
                caption: "Ne crache que les jours de repos.",
            },
            {
                id: "seal",
                name: "Phoque",
                caption: "Nageoires au chaud. Concurrence au frais.",
            },
            {
                id: "hamster",
                name: "Hamster",
                caption: "Petites pattes. Cardio déraisonnable.",
            },
            {
                id: "tree-frog",
                name: "Rainette",
                caption: "Les sauts comptent double. Paraît-il.",
            },
            {
                id: "mouse",
                name: "Souris",
                caption: "Petits pas. Tellement nombreux.",
            },
            {
                id: "guinea-pig",
                name: "Cochon d’Inde",
                caption: "Couine poliment. Marche sans relâche.",
            },
            {
                id: "duck",
                name: "Canard",
                caption:
                    "Petit canard. Grosse barre. Coin-coin encore plus gros.",
            },
            {
                id: "donkey",
                name: "Âne",
                caption: "Têtu sur le cardio. Dans le bon sens.",
            },
        ],
    },
    options: {
        eyebrow: "Options du défi",
        title: "Réglez-le",
        titleAccent: "à votre façon.",
        items: [
            ["Mesure", "Les pas. Le total le plus élevé gagne."],
            [
                "Durée",
                "3 jours, 1 semaine, 2 semaines, 1 mois ou vos propres dates.",
            ],
            [
                "Répétition",
                "La manche suivante démarre seule à la fin de la précédente.",
            ],
            [
                "Qui peut rejoindre",
                "Privé par défaut. Passez en public pour apparaître dans Rejoindre.",
            ],
            [
                "Invitation",
                "Un lien ou un code de 4 caractères. Les noms d’utilisateur sont facultatifs.",
            ],
            [
                "Gage du perdant",
                "Ce que vous voulez. Il reste affiché sur le défi.",
            ],
            ["Fil", "Photos, vidéos, messages et réactions pour chaque défi."],
            ["Rappels", "Des rappels facultatifs pendant un défi."],
        ],
    },
    pricing: {
        eyebrow: "Prix",
        tag: "Tout est inclus",
        free: "Gratuit",
        text: "Tous les défis, toutes les fonctions et les 12 compagnons. Sans pub. Sans suivi.",
        included: [
            "Défis illimités",
            "Classement et graphiques en direct",
            "Les 12 compagnons",
            "Fil, messages et réactions",
            "Synchronisation avec Santé d’Apple et WHOOP",
        ],
        later: "En option",
        extras: [
            [
                "Spécial",
                "0,99 €",
                "Achetez un compagnon spécial une fois et gardez-le pour toujours. Collectionnez-en autant que vous voulez.",
            ],
            [
                "À ton image",
                "2,99 €",
                "Décrivez n’importe quel animal et obtenez un compagnon personnalisé en cinq poses. Invitez un ami sur FitFight, et vous en recevez chacun un gratuit.",
            ],
        ],
    },
    faq: {
        eyebrow: "FAQ",
        title: "Vos questions, nos réponses.",
        note: "Vous ne trouvez pas la vôtre ? Posez-la dans l’onglet Retours de l’app.",
        search: "Rechercher une question",
        noMatch:
            "Aucun résultat. Posez votre question dans l’onglet Retours, où chacun vote pour les meilleures idées.",
        items: [
            [
                "Qu’est-ce que FitFight ?",
                "Une app iPhone gratuite pour se défier aux pas entre amis. Lancez un défi, tout le monde marche, et Santé d’Apple compte les pas. Le total le plus élevé gagne.",
            ],
            [
                "Comment mes pas sont-ils comptés ?",
                "FitFight lit les pas de Santé d’Apple, le même total que dans l’app Santé. Apple fusionne les pas de l’iPhone et de l’Apple Watch, donc rien n’est compté deux fois.",
            ],
            [
                "Mes amis ont-ils besoin de l’app ?",
                "Oui. Chaque participant a besoin de FitFight sur un iPhone. Envoyez-leur le lien ou le code, et ils rejoignent en un geste.",
            ],
            [
                "Combien de temps dure un défi ?",
                "Vous choisissez : 3 jours, 1 semaine, 2 semaines ou 1 mois, ou vos propres dates. Le défi se termine tout seul et le total le plus élevé gagne.",
            ],
            [
                "Que doit faire le perdant ?",
                "Ce que vous voulez. Écrivez le gage en lançant le défi, par exemple « Acheter les croissants ». Il reste affiché sur le défi, pour que personne n’oublie.",
            ],
            [
                "Qui voit mes pas ?",
                "Les participants de votre défi voient votre total, vos pas quotidiens dans le graphique du défi et votre rang. Personne ne reçoit vos données brutes de Santé d’Apple.",
            ],
            [
                "Qu’est-ce qu’un compagnon ?",
                "Un animal illustré qui vous représente dans les défis, le classement et le fil. Choisissez-en un parmi 12. Il change de pose à mesure que vos pas s’accumulent dans la journée.",
            ],
            [
                "Combien ça coûte ?",
                "Rien. FitFight est gratuit et sans pub. Les Spéciaux et les compagnons personnalisés sont des achats en option.",
            ],
            [
                "Est-ce que ça marche avec WHOOP ?",
                "Oui. Dans l’app, ouvrez Profil, puis Réglages, puis Connexions, et connectez WHOOP. FitFight récupère votre sommeil, votre récupération, votre effort et vos entraînements, mis à jour toutes les heures. Les pas des défis viennent toujours de Santé d’Apple : activez Santé d’Apple dans l’app WHOOP pour que vos pas WHOOP comptent.",
            ],
            [
                "Existe-t-il une app Android ?",
                "Pas pour le moment. FitFight compte les pas avec Santé d’Apple, donc l’app est réservée à l’iPhone.",
            ],
        ],
    },
    end: {
        title: "Vos amis marchent déjà.",
        text: "Lancez un défi ce soir. Réglez-le d’ici dimanche.",
        art: "Lapin, Tortue, Renard et Blaireau courent sur un sentier",
    },
    footer: {
        tagline: "Défiez vos amis. Bougez pour gagner.",
        privacy: ["Confidentialité", "/fr/privacy"],
        support: ["Assistance", "/fr/support"],
        otherLanguage: ["English", "/?lang=en", "en"],
    },
    phone: {
        tabs: ["Défis", "Nouveau", "Fil", "Retours", "Profil"],
        fightsTitle: "Défis",
        leading: "En tête dans 2 sur 4",
        stepsToday: "pas aujourd’hui",
        challenges: "Défis",
        segments: ["En cours", "Invités 1", "Passés"],
        ahead: "pas d’avance",
        behind: "pas de retard",
        newTitle: "Nouveau défi",
        newRule: "Pas. Le total le plus élevé gagne.",
        createOrJoin: "Créer ou rejoindre ?",
        createOrJoinText:
            "Lancez un nouveau défi ou rejoignez-en un déjà en cours.",
        create: "Créer",
        createText: "Lancer un nouveau défi",
        join: "Rejoindre",
        joinText: "Code, lien d’invitation, ou un défi public",
        feedTitle: "Fil",
        public: "Public",
        feedbackTitle: "Retours",
        feedbackSegments: ["Top", "Fonctions", "Bugs"],
        requests: [
            ["Résumé de la semaine le dimanche soir", "Fonction", "42"],
            ["Widget des pas du jour", "Fonction", "31"],
            ["Voir qui a le plus marché aujourd’hui", "Fonction", "24"],
            [
                "Les légendes du graphique se chevauchent sur les petits écrans",
                "Bug",
                "9",
            ],
        ],
        newRequest: "Nouvelle demande",
        copyUsername: "Copier le nom d’utilisateur",
        changeAnimal: "Changer d’animal",
        healthEyebrow: "Santé d’Apple",
        healthRow: "Pas de Santé d’Apple",
        connected: "Connecté",
        on: "Activé",
        settingsEyebrow: "Réglages",
        settings: [
            "Parrainer un ami",
            "Préférences",
            "Confidentialité",
            "Assistance",
            "Versions",
        ],
    },
};

export const landingCopy = { en, fr };

// The hero phone and the companion block count up to this many steps today.
export const sampleTodaySteps = 8432;

// Same thresholds as CompanionEffortStage.matching(todaySteps:) in the app.
export function companionPose(steps: number) {
    if (steps >= 15000) return 5;
    if (steps >= 10000) return 4;
    if (steps >= 6000) return 3;
    if (steps >= 3000) return 2;
    return 1;
}

export function formatSteps(steps: number, language: SiteLanguage) {
    return steps.toLocaleString(language === "fr" ? "fr-FR" : "en-US");
}
