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
        lede: "Start a private fight, let Apple Health keep the score, and find out who really walks the most.",
        tryIt: "Try it",
        meta: ["Free", "iPhone", "Apple Health"],
        betaMeta: ["iPhone", "Tap the TestFlight link twice", "Apple Health"],
        hint: "Tap the tabs. This is the real app.",
    },
    totalSteps: {
        caption: "steps recorded since people joined FitFight",
    },
    joiningLift: {
        before: "The typical member walks ",
        amount: (lift: number) => `${lift}% more`,
        after: " when using FitFight.",
        detail: (lift: number) =>
            `The typical member walks ${lift}% more a day in their first 4 weeks than in the 4 weeks before joining.`,
    },
    what: {
        eyebrow: "What it is",
        statement: [
            "FitFight is a step challenge between ",
            "you",
            " and ",
            "your friends",
            ". Pick a length, agree on what the loser does, then just walk. ",
            "Apple Health",
            " keeps the score.",
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
            name: "Weekend wanderers",
            left: "1 day and 7 hours left",
            gap: "+860",
            ahead: true,
            rival: "otter",
        },
        {
            name: "No lift, no mercy",
            left: "5 days left",
            gap: "−1,260",
            ahead: false,
            rival: "dog",
        },
        {
            name: "The croissant run",
            left: "2 days left",
            gap: "+2,840",
            ahead: true,
            rival: "badger",
        },
    ],
    standings: [
        { name: "You", animal: "fox", seen: "5 minutes ago", total: "61.2K" },
        {
            name: "Leo",
            animal: "badger",
            seen: "12 minutes ago",
            total: "58.4K",
        },
        { name: "Nina", animal: "otter", seen: "1 hour ago", total: "54.9K" },
    ],
    posts: [
        {
            who: "Leo",
            animal: "badger",
            ago: "12m",
            fight: "The croissant run",
            text: "Nine floors of stairs at lunch. Enjoy the lead while it lasts.",
            reacts: ["🔥 4", "😂 2"],
            comments: "3 comments",
        },
        {
            who: "Nina",
            animal: "otter",
            ago: "1h",
            fight: "Weekend wanderers",
            text: "Sunday loop done. 14,210 steps and zero regrets.",
            reacts: ["👏 5"],
            comments: "1 comment",
        },
        {
            who: "Sam",
            animal: "rabbit",
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
            "Walk to the bakery.",
            "Take the stairs.",
            "Get off one stop early.",
            "Say yes to the long way home.",
        ],
        win: "Beat Leo by 2,840.",
        gaps: [
            ["The croissant run", "+2,840", "steps ahead", "Relax. Or don’t."],
            [
                "No lift, no mercy",
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
                "Start a fight",
                "Pick how long it lasts, type what the loser has to do, and share the link with your friends.",
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
        tryIt: "Try it: the same five steps as the app.",
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
        titleText:
            "Both are optional. If you skip a title, the action is the name of the fight.",
        title: "Title",
        titlePlaceholder: "Weekend walk-off",
        action: "Loser action",
        actionPlaceholder: "Cook dinner",
        defaultTitle: "The croissant run",
        defaultAction: "Buy the croissants",
        reviewTitle: "Ready to fight?",
        reviewText: "Check the agreement before you start.",
        metric: "Metric",
        metricValue: "Steps · highest total wins",
        privateValue: "Join with code or invite link",
        usesAction: "Uses the action",
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
        theFight: "the fight",
        share: "Share invite",
        restart: "Start over",
    },
    companions: {
        eyebrow: "Companions",
        title: "Pick a companion.",
        titleAccent: "Watch it get moving.",
        lede: "Your companion stands in for you in fights, standings and the Feed. It changes pose as your steps add up during the day.",
        pick: "Pick your animal",
        walk: "Walk. It changes pose with your steps today.",
        stepsToday: "Steps today",
        poses: ["Resting", "Heading out", "On the move", "Pushing", "Peak"],
        ranges: ["Under 3k", "3k+", "6k+", "10k+", "15k+"],
        animals: [
            { id: "fox", name: "Fox", caption: "Just a little smug." },
            { id: "badger", name: "Badger", caption: "Quietly competitive." },
            { id: "otter", name: "Otter", caption: "Here for a good time." },
            { id: "rabbit", name: "Rabbit", caption: "Always one more lap." },
            { id: "raccoon", name: "Raccoon", caption: "Always has a plan." },
            {
                id: "red-panda",
                name: "Red Panda",
                caption: "Looks relaxed. Isn’t.",
            },
            { id: "bear", name: "Bear", caption: "Big strides. Soft heart." },
            { id: "boar", name: "Boar", caption: "A little unstoppable." },
            { id: "sloth", name: "Sloth", caption: "Slow is still forward." },
            { id: "dog", name: "Dog", caption: "Always up for a walk." },
            { id: "goat", name: "Goat", caption: "Takes the uphill route." },
            { id: "turtle", name: "Turtle", caption: "Never out of the race." },
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
            "Apple Health sync",
        ],
        later: "Coming later, optional",
        extras: [
            [
                "Specials",
                "€0.99",
                "One-of-one animals. Each has a single owner, for good.",
            ],
            [
                "Make it yours",
                "€4.99",
                "Describe any animal. Get your own companion in five poses.",
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
                "Nothing. FitFight is free, with no ads. Optional Specials and custom companions are coming later.",
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
        art: "Rabbit, Fox, Badger and Turtle playing tennis",
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
        tagline: "A little further.",
        taglineAccent: "Together.",
        stepsToday: "steps today",
        challenges: "Challenges",
        segments: ["Current", "Invited 1", "Past"],
        ahead: "steps ahead",
        behind: "steps behind",
        newTitle: "New fight",
        newTagline: "Good company.",
        newTaglineAccent: "A good excuse to walk.",
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
        lede: "Lancez un défi privé, laissez Santé d’Apple compter les pas et découvrez qui marche vraiment le plus.",
        tryIt: "Essayer",
        meta: ["Gratuit", "iPhone", "Santé d’Apple"],
        betaMeta: [
            "iPhone",
            "Ouvrez le lien TestFlight deux fois",
            "Santé d’Apple",
        ],
        hint: "Touchez les onglets. C’est la vraie app.",
    },
    totalSteps: {
        caption: "pas enregistrés depuis que chacun a rejoint FitFight",
    },
    joiningLift: {
        before: "Le membre type marche ",
        amount: (lift: number) => `${lift}\u202f% de plus`,
        after: " avec FitFight.",
        detail: (lift: number) =>
            `Le membre type marche ${lift}\u202f% de plus par jour pendant ses 4 premières semaines que pendant les 4 semaines avant son inscription.`,
    },
    what: {
        eyebrow: "Le principe",
        statement: [
            "FitFight est un défi de pas entre ",
            "vous",
            " et ",
            "vos amis",
            ". Choisissez une durée, mettez-vous d’accord sur le gage du perdant, puis marchez. ",
            "Santé d’Apple",
            " compte les pas.",
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
            name: "Les flâneurs du week-end",
            left: "Encore 1 jour et 7 heures",
            gap: "+860",
            ahead: true,
            rival: "otter",
        },
        {
            name: "Pas d’ascenseur, pas de pitié",
            left: "Encore 5 jours",
            gap: "−1 260",
            ahead: false,
            rival: "dog",
        },
        {
            name: "La course aux croissants",
            left: "Encore 2 jours",
            gap: "+2 840",
            ahead: true,
            rival: "badger",
        },
    ],
    standings: [
        {
            name: "Vous",
            animal: "fox",
            seen: "il y a 5 minutes",
            total: "61,2 k",
        },
        {
            name: "Leo",
            animal: "badger",
            seen: "il y a 12 minutes",
            total: "58,4 k",
        },
        {
            name: "Nina",
            animal: "otter",
            seen: "il y a 1 heure",
            total: "54,9 k",
        },
    ],
    posts: [
        {
            who: "Leo",
            animal: "badger",
            ago: "12 min",
            fight: "La course aux croissants",
            text: "Neuf étages d’escaliers à midi. Profitez de votre avance tant qu’elle dure.",
            reacts: ["🔥 4", "😂 2"],
            comments: "3 commentaires",
        },
        {
            who: "Nina",
            animal: "otter",
            ago: "1 h",
            fight: "Les flâneurs du week-end",
            text: "Boucle du dimanche bouclée. 14 210 pas et zéro regret.",
            reacts: ["👏 5"],
            comments: "1 commentaire",
        },
        {
            who: "Sam",
            animal: "rabbit",
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
            "Marchez jusqu’à la boulangerie.",
            "Prenez l’escalier.",
            "Descendez un arrêt plus tôt.",
            "Rentrez par le chemin le plus long.",
        ],
        win: "Battez Leo de 2 840 pas.",
        gaps: [
            [
                "La course aux croissants",
                "+2 840",
                "pas d’avance",
                "Détendez-vous. Ou pas.",
            ],
            [
                "Pas d’ascenseur, pas de pitié",
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
                "Lancez un défi",
                "Choisissez sa durée, écrivez le gage du perdant et partagez le lien avec vos amis.",
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
        tryIt: "Essayez : les cinq mêmes étapes que dans l’app.",
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
        titleText:
            "Les deux sont facultatifs. Sans titre, le gage devient le nom du défi.",
        title: "Titre",
        titlePlaceholder: "Défi du week-end",
        action: "Gage du perdant",
        actionPlaceholder: "Préparer le dîner",
        defaultTitle: "La course aux croissants",
        defaultAction: "Acheter les croissants",
        reviewTitle: "Prêt pour le défi ?",
        reviewText: "Vérifiez l’accord avant de lancer.",
        metric: "Mesure",
        metricValue: "Pas · le total le plus élevé gagne",
        privateValue: "Rejoindre avec le code ou le lien d’invitation",
        usesAction: "Utilise le gage",
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
        theFight: "le défi",
        share: "Partager l’invitation",
        restart: "Recommencer",
    },
    companions: {
        eyebrow: "Compagnons",
        title: "Choisissez un compagnon.",
        titleAccent: "Regardez-le bouger.",
        lede: "Votre compagnon vous représente dans les défis, le classement et le fil. Il change de pose à mesure que vos pas s’accumulent dans la journée.",
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
            { id: "fox", name: "Renard", caption: "Juste un peu fier de lui." },
            {
                id: "badger",
                name: "Blaireau",
                caption: "L’esprit de compétition, en douceur.",
            },
            {
                id: "otter",
                name: "Loutre",
                caption: "Là pour passer un bon moment.",
            },
            {
                id: "rabbit",
                name: "Lapin",
                caption: "Toujours un tour de plus.",
            },
            {
                id: "raccoon",
                name: "Raton Laveur",
                caption: "A toujours un plan.",
            },
            {
                id: "red-panda",
                name: "Panda Roux",
                caption: "A l’air détendu. En apparence.",
            },
            {
                id: "bear",
                name: "Ours",
                caption: "De grands pas. Un cœur tendre.",
            },
            { id: "boar", name: "Sanglier", caption: "Un peu inarrêtable." },
            {
                id: "sloth",
                name: "Paresseux",
                caption: "Lentement, mais en avant.",
            },
            {
                id: "dog",
                name: "Chien",
                caption: "Toujours partant pour une balade.",
            },
            {
                id: "goat",
                name: "Chèvre",
                caption: "Prend le chemin qui monte.",
            },
            {
                id: "turtle",
                name: "Tortue",
                caption: "Toujours dans la course.",
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
            "Synchronisation avec Santé d’Apple",
        ],
        later: "Plus tard, en option",
        extras: [
            [
                "Spéciaux",
                "0,99 €",
                "Des animaux uniques. Chacun n’a qu’un seul propriétaire, pour de bon.",
            ],
            [
                "À ton image",
                "4,99 €",
                "Décrivez n’importe quel animal. Obtenez votre propre compagnon en cinq poses.",
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
                "Rien. FitFight est gratuit et sans pub. Des Spéciaux et des compagnons personnalisés, en option, arriveront plus tard.",
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
        art: "Lapin, Renard, Blaireau et Tortue jouent au tennis",
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
        tagline: "Un peu plus loin.",
        taglineAccent: "Ensemble.",
        stepsToday: "pas aujourd’hui",
        challenges: "Défis",
        segments: ["En cours", "Invités 1", "Passés"],
        ahead: "pas d’avance",
        behind: "pas de retard",
        newTitle: "Nouveau défi",
        newTagline: "Bien accompagné.",
        newTaglineAccent: "Une bonne excuse pour marcher.",
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
