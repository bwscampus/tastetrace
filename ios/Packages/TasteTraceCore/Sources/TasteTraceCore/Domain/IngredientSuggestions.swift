import Foundation

/// The ingredients a food's name already tells us: "Chicken salad" → chicken,
/// "Turkey sandwich" → turkey, bread. A starting list the person checks and
/// finishes on Verify Ingredients, never a guess at the whole recipe.
///
/// Phrases are matched longest first, so "peanut butter" is one ingredient and
/// never also "butter", and "mac and cheese" is pasta and cheese.
public func suggestedIngredients(forFood name: String) -> [String] {
    let words = name.lowercased()
        .folding(options: .diacriticInsensitive, locale: nil)
        .components(separatedBy: CharacterSet.letters.inverted)
        .filter { !$0.isEmpty }

    var found: [String] = []
    var index = 0
    while index < words.count {
        var matched = false
        for length in stride(from: min(IngredientVocabulary.longestPhrase, words.count - index), through: 1, by: -1) {
            if let names = IngredientVocabulary.lookup(Array(words[index..<index + length])) {
                found.append(contentsOf: names)
                index += length
                matched = true
                break
            }
        }
        if !matched { index += 1 }
    }

    var seen = Set<String>()
    return found.filter { seen.insert($0).inserted }
}

enum IngredientVocabulary {
    /// Dishes whose name implies a base ingredient the person might not think to add.
    static let dishes: [String: [String]] = [
        "sandwich": ["bread"], "sub": ["bread"], "toast": ["bread"], "panini": ["bread"],
        "burrito": ["tortilla"], "taco": ["tortilla"], "wrap": ["tortilla"],
        "quesadilla": ["tortilla", "cheese"], "nachos": ["tortilla chips", "cheese"],
        "pizza": ["pizza dough", "cheese", "tomato sauce"],
        "mac and cheese": ["pasta", "cheese"], "macaroni and cheese": ["pasta", "cheese"],
        "grilled cheese": ["bread", "cheese", "butter"],
        "burger": ["bun"], "hamburger": ["beef", "bun"], "cheeseburger": ["beef", "bun", "cheese"],
        "hot dog": ["hot dog", "bun"],
        "omelette": ["egg"], "omelet": ["egg"], "frittata": ["egg"],
        "fried rice": ["rice", "egg"], "ramen": ["ramen noodles"],
        "pb j": ["peanut butter", "jelly", "bread"],
        "latte": ["coffee", "milk"], "cappuccino": ["coffee", "milk"],
        "milkshake": ["milk", "ice cream"], "oatmeal": ["oats"],
        "fries": ["potato"], "french fries": ["potato"], "sweet potato fries": ["sweet potato"], "hash browns": ["potato"],
        "guacamole": ["avocado"], "hummus": ["chickpeas"],
        "marinara": ["tomato sauce"], "sushi": ["rice", "seaweed"],
    ]

    /// Ingredient words and phrases, with the name they're logged under.
    static let ingredients: [String: String] = {
        var map: [String: String] = [:]
        let plain = [
            // Proteins
            "chicken", "beef", "steak", "pork", "bacon", "ham", "sausage", "turkey", "lamb", "salmon",
            "tuna", "shrimp", "fish", "cod", "tilapia", "crab", "lobster", "tofu", "tempeh", "egg",
            "pepperoni", "salami", "chorizo", "prosciutto",
            // Grains and breads
            "rice", "brown rice", "quinoa", "oats", "pasta", "spaghetti", "noodles", "bread", "bagel",
            "tortilla", "croissant", "couscous", "cereal", "granola", "crackers", "bun", "pita", "naan",
            "corn", "barley", "sourdough bread", "tortilla chips",
            // Dairy
            "cheese", "cheddar", "mozzarella", "parmesan", "feta", "goat cheese", "cream cheese",
            "yogurt", "greek yogurt", "milk", "butter", "cream", "sour cream", "ice cream", "whipped cream",
            // Vegetables and legumes
            "lettuce", "romaine", "spinach", "kale", "arugula", "tomato", "cucumber", "onion", "garlic",
            "bell pepper", "jalapeno", "avocado", "broccoli", "cauliflower", "carrot", "celery", "mushroom",
            "potato", "sweet potato", "zucchini", "eggplant", "beans", "black beans", "chickpeas", "lentils",
            "peas", "green beans", "cabbage", "seaweed", "kimchi", "sauerkraut",
            // Fruit
            "apple", "banana", "berries", "strawberry", "blueberry", "raspberry", "orange", "lemon", "lime",
            "mango", "pineapple", "grape", "peach", "pear", "watermelon", "cherry", "coconut",
            // Nuts and seeds
            "peanut", "peanut butter", "almond", "almond butter", "walnut", "cashew", "pecan", "pistachio",
            "sesame",
            // Sauces, sweets and drinks
            "chocolate", "honey", "sugar", "maple syrup", "jam", "jelly", "ketchup", "mustard", "soy sauce",
            "hot sauce", "salsa", "ranch", "pesto", "olive oil", "tomato sauce", "teriyaki sauce",
            "coffee", "tea", "green tea", "matcha", "wine", "beer", "soda", "orange juice",
        ]
        for name in plain { map[name] = name }
        let aliases = [
            "eggs": "egg", "yoghurt": "yogurt", "mayo": "mayonnaise", "mayonnaise": "mayonnaise",
            "sourdough": "sourdough bread", "oat": "oats", "noodle": "noodles", "potatoes": "potato",
            "tomatoes": "tomato", "berry": "berries", "chickpea": "chickpeas", "garbanzo": "chickpeas",
            "bean": "beans", "lentil": "lentils", "pea": "peas",
            "parm": "parmesan", "teriyaki": "teriyaki sauce", "cracker": "crackers",
        ]
        for (alias, name) in aliases { map[alias] = name }
        return map
    }()

    static let longestPhrase = (Array(dishes.keys) + Array(ingredients.keys))
        .map { $0.split(separator: " ").count }.max() ?? 1

    /// The ingredients for one run of words, trying a plural's singular too
    /// ("strawberries", "tomatoes", "almonds").
    static func lookup(_ words: [String]) -> [String]? {
        let phrase = words.joined(separator: " ")
        for candidate in [phrase] + singulars(of: phrase) {
            if let names = dishes[candidate] { return names }
            if let name = ingredients[candidate] { return [name] }
        }
        return nil
    }

    private static func singulars(of phrase: String) -> [String] {
        var result: [String] = []
        if phrase.hasSuffix("ies") { result.append(String(phrase.dropLast(3)) + "y") }
        if phrase.hasSuffix("es") { result.append(String(phrase.dropLast(2))) }
        if phrase.hasSuffix("s") { result.append(String(phrase.dropLast())) }
        return result
    }
}
