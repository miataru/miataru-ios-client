import Foundation

/// Multilingual keyword mappings for navigation maneuver detection.
/// 
/// ## Why This Mapping Is Necessary
/// 
/// MapKit's `MKRouteStep.instructions` provides only localized, free-text navigation instructions
/// (e.g., "Turn left onto Main Street" in English, "Links abbiegen auf Hauptstraße" in German).
/// Unlike routing SDKs like Mapbox or HERE, MapKit does NOT expose typed maneuver enums
/// (e.g., `ManeuverType.left`, `ManeuverModifier.slight`) that would work consistently across locales.
/// 
/// This creates a fundamental problem: to display appropriate navigation arrows/icons,
/// we must parse the localized text to determine the maneuver type. However, text parsing
/// is inherently fragile and locale-dependent.
/// 
/// ## Our Solution: Hybrid Approach
/// 
/// 1. **Primary**: Multilingual keyword mapping (this file) - robust across supported locales
/// 2. **Fallback**: Geometry-based angle detection between route step polylines
/// 3. **Final fallback**: Default to straight arrow
/// 
/// This approach prioritizes accuracy from MapKit's localized text while providing
/// geometric fallbacks when text parsing fails or is ambiguous.
/// 
/// ## Alternative Approaches (and why we don't use them)
/// 
/// - **Pure geometry**: Unreliable for complex intersections, roundabouts, highway ramps
/// - **English-only parsing**: Breaks completely in non-English locales
/// - **Switch to Mapbox/HERE**: Requires changing the entire routing backend
/// 
/// ## Contributing
/// 
/// To add support for your language:
/// 1. Add tokens to the appropriate arrays below
/// 2. Include common variants, gendered forms, and synonyms
/// 3. Keep tokens lowercase; accents are fine
/// 4. Prefer short substrings that are unlikely to conflict
/// 5. Test with real MapKit instructions from your locale
/// 
/// ## Data provenance and coverage
/// 
/// Many tokens were extracted from a multilingual MapKit walking route sample:
/// `Sample/NavigationRouteInstructionExtractor/output/2025-10-12-RouteInstructions-1760278219-ToykoRoute.json`.
/// We covered the following BCP-47 language codes (or their regional variants) listed in
/// `defaultLanguages`: ar, bg, ca, cs, da, de, el, en, en-GB, en-US, es, es-MX, et, fi, fr, fr-CA,
/// he, hi, hr, hu, id, it, ja, ko, lt, lv, nb, nl, pl, pt, pt-BR, ro, ru, sk, sl, sr, sv, th, tr,
/// uk, vi, zh, zh-Hans, zh-Hant.
/// 
/// Detection priority in parsing (see `NavigationInstruction.symbolFromLocalizedInstruction`):
/// 1) U-turn 2) Arrive 3) Start 4) Feature (tunnel/bridge/escalator/stairs/cross) 5) Modifiers
/// (slight/sharp) + Direction (left/right). If none match, geometry fallback or straight default.
struct LocalizedManeuverTokens {
    
    // MARK: - U-turn Detection
    
    /// Substrings that identify U-turn maneuvers across supported locales.
    /// - Usage: Lowercase `MKRouteStep.instructions` and check for `contains` of any token.
    /// - Effect: If matched, classify the step as a U-turn regardless of left/right modifiers.
    static let uTurnTokens = [
        // English
        "u-turn", "uturn", "make a u", "make a u turn",
        // German
        "umkehren", "kehr um", "wenden", "umdrehen",
        // French
        "demi-tour", "demi tour",
        // Spanish
        "vuelta en u", "giro en u", "media vuelta", "dar la vuelta",
        // Italian
        "inversione a u", "inversione ad u",
        // Portuguese
        "retorno", "retornar", "inversão de marcha", "inversao de marcha",
        // Dutch
        "keer om", "omkeren", "draai om", "keren",
        // Swedish
        "u-sväng", "u sväng", "vänd", "vänd om",
        // Norwegian
        "u-sving", "u sving", "snu",
        // Danish
        "u-vending", "u vending", "vend om",
        // Finnish
        "u-käännös", "u kaannos",
        // Japanese
        "ユーターン", "uターン", "転回",
        // Chinese (Simplified/Traditional)
        "掉头", "调头", "掉頭", "調頭",
        // Russian
        "разворот", "развернитесь",
        // Polish
        "zawróć", "zawroc", "zawracaj",
        // Czech
        "otočte se", "obrat",
        // Slovak
        "otočte sa",
        // Hungarian
        "forduljon meg", "megfordulás",
        // Romanian
        "întoarcere", "intoarcere", "întoarceți", "intoarceti",
        // Greek
        "αναστροφή", "κάντε αναστροφή",
        // Turkish
        "u dönüşü", "u donusu", "geri dön", "geri don",
        // Ukrainian
        "розворот", "розверніться",
        // Bulgarian
        "обратен завой"
    ]
    
    // MARK: - Crossing / Tunnel / Bridge / Vertical Movement
    
    /// Substrings indicating a crossing action (cross over/through an intersecting road/path).
    /// Useful to render a dedicated crosswalk icon if desired; otherwise can be treated as straight.
    static let crossTokens = [
        // English
        "cross ", "crossing",
        // Arabic
        "اعبر",
        // Finnish
        "ylitä",
        // Catalan
        "travessa",
        // Hindi
        "पार करें",
        // Swedish/Danish/Norwegian
        "gå över", "gå over",
        // Dutch
        "steek",
        // Italian
        "attraversa",
        // Portuguese
        "atravesse",
        // Greek
        "διασχίστε",
        // Czech
        "přejděte",
        // Norwegian
        "kryss",
        // Croatian
        "prijeđite",
        // Russian
        "пересеките",
        // Polish
        "przejdź",
        // Indonesian/Malay
        "seberangi",
        // Vietnamese
        "đi qua",
        // Chinese (Simplified/Traditional)
        "穿过", "穿過",
        // Turkish
        "karşıya geç",
        // Korean
        "건너",
        // Japanese
        "渡り", "渡って",
        // Spanish/Portuguese
        "cruce", "cruza", "cruzar", "cruce el",
        // French
        "traversez",
        // German
        "überqueren", "überquere", "ueberqueren"
    ]
    
    /// Substrings indicating a tunnel traversal.
    static let tunnelTokens = [
        // English/German
        "tunnel",
        // Arabic
        "النفق",
        // Korean
        "터널",
        // Turkish
        "tünel",
        // Thai
        "อุโมงค์",
        // Catalan/Spanish
        "túnel",
        // Hindi
        "सुरंग",
        // Croatian
        "tunel",
        // Czech
        "tunelu",
        // Danish
        "tunnellen",
        // Greek
        "σήραγγα",
        // Hebrew
        "מנהרה",
        // Russian
        "тоннель", "тоннел",
        // Chinese (Simplified/Traditional)
        "隧道",
        // Spanish/Italian/French variants
        // Japanese (walk through the tunnel)
        "トンネル"
    ]
    
    /// Substrings indicating a bridge traversal.
    static let bridgeTokens = [
        // English/French/Catalan variants
        "bridge", "pont",
        // Arabic
        "الجسر",
        // Dutch
        "brug",
        // Danish/Norwegian/Swedish
        "bro", "broen",
        // Finnish
        "silta",
        // Greek
        "γέφυρα",
        // Hebrew
        "גשר",
        // Italian/Portuguese
        "ponte",
        // Hindi
        "ब्रिज",
        // Czech
        "most",
        // Croatian
        
        // Russian
        "мост",
        // Turkish
        "köprü",
        // Korean
        "다리",
        // Japanese
        "橋",
        // Spanish/Portuguese
        "puente",
        // German
        "brücke", "bruecke",
        // Chinese (Simplified/Traditional)
        "天桥", "天橋"
    ]
    
    /// Substrings indicating use of an escalator.
    static let escalatorTokens = [
        // English
        "escalator",
        // Arabic
        "السلم المتحرك",
        // Indonesian
        "eskalator",
        // Turkish
        "yürüyen merdiven",
        // Spanish/Portuguese
        "escalera mecánica", "escada rolante",
        // Catalan
        "escales mecàniques",
        // Czech
        "eskalátorem",
        // Hindi
        "एस्केलेटर",
        // Norwegian
        "rulletrapp", "rulletrappen",
        // Dutch
        "roltrap",
        // German
        "rolltreppe",
        // Italian
        "scale mobili",
        // Greek
        "κυλιόμενες σκάλες",
        // Japanese
        "エスカレータ",
        // Finnish
        "liukuportaat", "liukuportailla",
        // Swedish/Danish
        "rulltrappa", "rulletrappe",
        // Chinese (Simplified/Traditional)
        "自动扶梯", "自動扶梯"
    ]
    
    /// Substrings indicating use of stairs.
    static let stairsTokens = [
        // English
        "stairs",
        // Arabic
        "الدرج",
        // Turkish
        "merdiven",
        // Spanish/Portuguese
        "escaleras", "escadas",
        // French
        "escaliers",
        // Catalan
        "escales",
        // Czech
        "schodech", "schody",
        // Hindi
        "सीढ़ियों",
        // Norwegian
        "trapp",
        // Dutch
        "trap", "trappen",
        // Croatian
        "stepenice",
        // German
        "treppe", "treppen",
        // Italian
        "scale",
        // Greek
        "σκάλες",
        // Japanese
        "階段",
        // Finnish
        "portaat", "portaita", "portailla",
        // Swedish/Danish
        "trappa",
        // Chinese (Simplified/Traditional)
        "楼梯", "樓梯"
    ]

    // MARK: - Route Start Detection
    /// Substrings that typically appear in the very first instruction to move toward or begin the route.
    static let startTokens = [
        // English
        "proceed to the route",
        // Arabic
        "استمر إلى المسار",
        // Bulgarian (and similar Cyrillic sample)
        "продължете към маршрута",
        // Catalan
        "ves a l’inici de la ruta", "ves a l'inici de la ruta",
        // Czech / Slovak
        "pokračujte po trase",
        // Danish
        "fortsæt til ruten",
        // German
        "weiter auf der route", "starten",
        // Greek
        "προχωρήστε στη διαδρομή",
        // Spanish
        "ve al inicio de la ruta", "regresa a la ruta",
        // Russian
        "следуйте по маршруту",
        // Finnish
        "jatka reitille",
        // French
        "rejoignez l’itinéraire", "rejoignez l'itinéraire",
        // Hebrew
        "המשך/י", "המשך",
        // Hindi
        "मार्ग की ओर बढ़ें",
        // Croatian
        "nastavite po ruti",
        // Hungarian
        "menjen az útvonal felé",
        // Indonesian
        "lanjut ke rute",
        // Italian
        "procedi verso l’itinerario", "procedi verso l'itinerario",
        // Japanese
        "経路へ進む",
        // Korean
        "경로를 따라 계속 이동",
        // Lithuanian
        "toliau eikite į maršruto kelią",
        // Norwegian Bokmål
        "fortsett til ruten",
        // Dutch
        "ga naar de route",
        // Polish
        "znajdź początek trasy",
        // Portuguese
        "siga para a rota",
        // Romanian
        "începeți ruta", "incepeti ruta",
        // Slovenian
        "nadaljujte do poti",
        // Swedish
        "fortsätt till rutten",
        // Chinese (Simplified)
        "前往这条路线"
    ]
    
    // MARK: - Arrival Detection
    
    /// Substrings that indicate arrival at or near the destination.
    /// - Usage: Match to mark terminal steps and suppress maneuver arrows in the UI.
    /// - Effect: Signals end-of-route messaging rather than a turn/continue instruction.
    static let arriveTokens = [
        // English
        "arrive", "arrival", "you have arrived",
        // German
        "ankommen", "ziel", "sie haben ihr ziel erreicht",
        // French
        "arrivée", "arriver", "vous êtes arrivé", "vous etes arrive",
        // Spanish
        "llegada", "llegue", "llegar", "ha llegado", "has llegado",
        // Italian
        "arrivo", "arrivare", "sei arrivato", "siete arrivati",
        // Portuguese
        "chegada", "você chegou", "voce chegou", "chegou",
        // Dutch
        "u bent gearriveerd", "aankomst", "u bent aangekomen",
        // Swedish
        "du är framme", "ni är framme", "ankomst",
        // Norwegian
        "du er fremme",
        // Danish
        // Finnish
        "olet perillä", "saapuminen",
        // Japanese
        "到着",
        // Chinese (Simplified/Traditional)
        "到达", "到達", "您已到达", "你已到达", "您已到達", "你已到達",
        // Russian
        "вы прибыли", "прибытие", "прибудете",
        // Polish
        "dotarłeś", "dotarliście", "dojechałeś", "dojechaliście", "jesteś u celu",
        // Czech
        "dorazili jste", "jste v cíli", "dojeli jste", "příjezd",
        // Slovak
        "dorazili ste", "ste v cieli", "príchod",
        // Hungarian
        "megérkeztél", "megérkezett", "érkezés",
        // Romanian
        "ați ajuns", "ati ajuns", "sosire",
        // Greek
        "φτάσατε", "άφιξη", "αφιξη",
        // Turkish
        "vardınız", "ulaştınız", "ulastiniz", "varış",
        // Ukrainian
        "ви прибули", "прибуття",
        // Bulgarian
        "пристигнахте", "пристигане",
        // Arabic
        "الوجهة", "الوجهة على يمينك",
        // Hebrew
        "היעד", "היעד בצד ימין",
        // Korean
        "목적지", "오른쪽에 목적지가",
        // Thai
        "ปลายทาง", "ปลายทางอยู่ทางขวามือของคุณ",
        // Vietnamese
        "điểm đến",
        // Indonesian
        "tujuan",
        // Lithuanian
        "kelionės tikslas",
        // Catalan
        "la destinació",
        // Hindi
        "मंज़िल",
        // Norwegian (arrival phrasing)
        "du er ankommet", "ankommet",
        // Croatian (destination phrasing)
        "odredište je",
        // Russian (destination phrasing)
        "пункт назначения",
        // English (fallback locales)
        "destination is",
        // German
        "das ziel befindet sich",
        // Dutch
        "bestemming is",
        // Danish
        "destinationen er",
        // Greek
        "ο προορισμός",
        // Italian
        "la destinazione",
        // Polish
        "cel znajduje się",
        // Portuguese (pt/pt-br)
        "o destino está",
        // Czech
        "cíl je",
        // Norwegian Bokmål
        "bestemmelsesstedet er",
        // Bulgarian
        "дестинацията е",
        // Chinese (Simplified/Traditional)
        "目的地在你右侧", "目的地在你的右邊", "目的地",
        // Japanese
        
    ]
    
    // MARK: - Modifier Detection
    
    /// Modifier tokens that soften the direction (slight/soft/bear).
    /// - Usage: Combine with `leftTokens`/`rightTokens` to infer "slight left" or "slight right".
    /// - Note: All tokens are lowercase; callers should lowercase instructions before matching.
    static let slightTokens = [
        // English
        "slight", "slightly", "bear right", "bear left", "half",
        // German
        "leicht", "halb",
        // French
        "légère", "legere",
        // Spanish
        "ligera", "ligero", "ligeramente",
        // Italian
        "leggera", "leggermente",
        // Portuguese
        "leve", "levemente", "ligeiramente", "meia",
        // Dutch
        "licht",
        // Swedish/Norwegian/Danish
        "svagt", "svag", "lett", "halv",
        // Japanese
        "やや", "少し",
        // Chinese (Simplified/Traditional)
        "稍向", "略向", "稍微",
        // Russian
        "слегка", "немного",
        // Polish
        "lekko", "nieznacznie", "pół",
        // Czech
        "mírně", "lehce", "půl",
        // Slovak
        "mierne",
        // Hungarian
        "enyhén", "kicsit",
        // Romanian
        "uşor", "usor",
        // Greek
        "ελαφρά", "ελαφριά",
        // Turkish
        "hafif", "biraz",
        // Finnish
        "loivasti", "hieman", "puoli",
        // Ukrainian
        "злегка", "незначно",
        // Bulgarian
        "леко",
        // Arabic
        "بسيط",
        // Hebrew
        "פניה קלה", "פנייה קלה",
        // Korean
        "완만히",
        // Thai
        "เบี่ยง",
        // Indonesian
        "sedikit",
        // Lithuanian
        "nežymiai",
        // Catalan
        "gir suau", "suau",
        // Hindi
        "थोड़ा", "थोडा",
        // Dutch
        "flauwe", "flauwe bocht",
        // Portuguese
        "suave", "curva suave",
        // Danish
        "blødt",
        // Greek
        "ανοιχτή"
    ]
    
    /// Modifier tokens that strengthen the direction (sharp/hard).
    /// - Usage: Combine with direction tokens to infer "sharp left" or "sharp right".
    /// - Note: Helps distinguish tight turns from normal turns when text explicitly says so.
    static let sharpTokens = [
        // English
        "sharp",
        // German
        "scharf",
        // French
        "serrée", "serre",
        // Spanish/Portuguese
        "pronunciada", "pronunciado",
        // Spanish
        "cerrada",
        // Italian
        "stretta", "brusca",
        // Dutch/Scandinavian catch
        "scherp", "skarpt",
        // Japanese
        "急",
        // Chinese (Simplified/Traditional)
        "急转", "急轉",
        // Russian
        "резко",
        // Polish
        "ostro",
        // Czech
        "prudce", "ostře",
        // Slovak
        "prudko",
        // Hungarian
        "élesen",
        // Romanian
        "brusc",
        // Greek
        "απότομα",
        // Turkish
        "keskin",
        // Finnish
        "jyrkästi", "jyrkkä",
        // Ukrainian
        "різко", "круто",
        // Bulgarian
        "рязко"
    ]
    
    // MARK: - Direction Detection
    
    /// Direction tokens for leftward maneuvers.
    /// - Usage: Paired with modifier tokens (e.g., `slightTokens`, `sharpTokens`) to build the final maneuver: slight/normal/sharp left.
    /// - Note: Some locales use compounds (e.g., Dutch "linksaf"); prefer `contains` over whole-word matches.
    static let leftTokens = [
        // English
        "left",
        // German
        "links",
        // French
        "gauche",
        // Spanish
        "izquierda",
        // Italian
        "sinistra",
        // Portuguese
        "esquerda", "à esquerda", "a esquerda",
        // Dutch
        "linksaf", "links af",
        // Nordic
        "venstre", "vänster",
        // Japanese
        "左に", "左へ", "左折", "左方向", "ひだり",
        // Chinese (Simplified/Traditional)
        "左转", "左轉", "向左",
        // Russian
        "налево", "лево",
        // Polish
        "w lewo", "lewo",
        // Czech
        "vlevo", "doleva",
        // Slovak
        "vľavo", "doľava",
        // Hungarian
        "balra",
        // Romanian
        "la stânga", "stânga", "la stanga",
        // Greek
        "αριστερά",
        // Turkish
        "sola", "sol",
        // Finnish
        "vasemmalle",
        // Ukrainian
        "наліво", "ліворуч",
        // Bulgarian
        "наляво",
        // Slovenian
        "levo",
        // Croatian/Serbian/Bosnian
        "lijevo", "levo",
        // Arabic
        "يسار", "يسارًا",
        // Hebrew
        "שמאלה",
        // Korean
        "좌회전",
        // Thai
        "เลี้ยวซ้าย",
        // Vietnamese
        "rẽ trái",
        // Indonesian
        "kiri", "ambil kiri", "belok kiri",
        // Lithuanian
        "kairėn", "į kairę",
        // Catalan
        "a l’esquerra", "a l'esquerra", "l’esquerra", "l'esquerra",
        // Hindi
        "बाएँ", "बाएं",
        // Norwegian
        
        // Czech
        
        // Croatian
        
    ]
    
    /// Direction tokens for rightward maneuvers.
    /// - Usage: Paired with modifier tokens (e.g., `slightTokens`, `sharpTokens`) to build the final maneuver: slight/normal/sharp right.
    /// - Note: Includes spacing and diacritic variants for better recall across locales.
    static let rightTokens = [
        // English
        "right",
        // German
        "rechts",
        // French
        "droite",
        // Spanish
        "derecha",
        // Italian
        "destra",
        // Portuguese
        "direita", "à direita", "a direita",
        // Dutch
        "rechtsaf", "rechts af",
        // Nordic
        "højre", "höger", "høyre", "hoyre",
        // Japanese
        "右に", "右へ", "右折", "右方向", "みぎ",
        // Chinese (Simplified/Traditional)
        "右转", "右轉", "向右",
        // Russian
        "направо", "право",
        // Polish
        "w prawo", "prawo",
        // Czech
        "vpravo", "doprava",
        // Slovak
        "vpravo", "doprava",
        // Hungarian
        "jobbra",
        // Romanian
        "la dreapta", "dreapta",
        // Greek
        "δεξιά",
        // Turkish
        "sağa", "saga", "sağ", "sag",
        // Finnish
        "oikealle",
        // Ukrainian
        "праворуч",
        // Bulgarian
        "надясно",
        // Slovenian
        "desno",
        // Croatian/Serbian/Bosnian
        "desno",
        // Arabic
        "يمين", "يمينًا",
        // Hebrew
        "ימינה",
        // Korean
        "우회전",
        // Thai
        "เลี้ยวขวา",
        // Vietnamese
        "rẽ phải",
        // Indonesian
        "kanan", "ambil kanan", "belok kanan",
        // Lithuanian
        "dešinėn", "į dešinę",
        // Catalan
        "a la dreta", "la dreta",
        // Hindi
        "दाएँ", "दाएं",
        // Norwegian
        
        // Czech
        
        // Croatian
        
    ]
}
