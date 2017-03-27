//
//  RandomNamer.m
//  FCModelTest
//
//  Created by Marco Arment on 9/14/13.
//  Copyright (c) 2013 Marco Arment. All rights reserved.
//

#import <Security/Security.h>
#import "RandomThings.h"

@implementation RandomThings

+ (NSString *)randomName
{
    static NSArray *randomNames = NULL;
    if (! randomNames) randomNames = @[
        @"Michael", @"Christopher", @"Matthew", @"Joshua", @"David", @"James", @"Daniel", @"Robert", @"John", @"Joseph", @"Jason", @"Justin", @"Andrew", @"Ryan", @"William", @"Brian",
        @"Brandon", @"Jonathan", @"Nicholas", @"Anthony", @"Eric", @"Adam", @"Kevin", @"Thomas", @"Steven", @"Timothy", @"Richard", @"Jeremy", @"Jeffrey", @"Kyle", @"Benjamin", 
        @"Aaron", @"Charles", @"Mark", @"Jacob", @"Stephen", @"Patrick", @"Scott", @"Nathan", @"Paul", @"Sean", @"Travis", @"Zachary", @"Dustin", @"Gregory", @"Kenneth", @"Jose", 
        @"Tyler", @"Jesse", @"Alexander", @"Bryan", @"Samuel", @"Derek", @"Bradley", @"Chad", @"Shawn", @"Edward", @"Jared", @"Cody", @"Jordan", @"Peter", @"Corey", @"Keith", 
        @"Marcus", @"Juan", @"Donald", @"Ronald", @"Phillip", @"George", @"Cory", @"Joel", @"Shane", @"Douglas", @"Antonio", @"Raymond", @"Carlos", @"Brett", @"Gary", @"Alex", 
        @"Nathaniel", @"Craig", @"Ian", @"Luis", @"Derrick", @"Erik", @"Casey", @"Philip", @"Frank", @"Evan", @"Gabriel", @"Victor", @"Vincent", @"Larry", @"Austin", @"Brent", @"Seth", 
        @"Wesley", @"Dennis", @"Todd", @"Christian", @"Curtis", @"Jeffery", @"Randy", @"Jeremiah", @"Adrian", @"Jesus", @"Luke", @"Alan", @"Trevor", @"Russell", @"Mario", @"Lucas", 
        @"Jerry", @"Miguel", @"Carl", @"Blake", @"Cameron", @"Mitchell", @"Troy", @"Tony", @"Shaun", @"Terry", @"Johnny", @"Martin", @"Ricardo", @"Bobby", @"Johnathan", @"Allen", 
        @"Devin", @"Jorge", @"Andre", @"Henry", @"Billy", @"Caleb", @"Marc", @"Garrett", @"Ricky", @"Kristopher", @"Francisco", @"Danny", @"Manuel", @"Lee", @"Lawrence", @"Jonathon", 
        @"Jimmy", @"Lance", @"Taylor", @"Randall", @"Micheal", @"Mathew", @"Albert", @"Jamie", @"Isaac", @"Roger", @"Rodney", @"Roberto", @"Jon", @"Colin", @"Walter", @"Clinton", 
        @"Louis", @"Clayton", @"Willie", @"Arthur", @"Chase", @"Joe", @"Jack", @"Jay", @"Angel", @"Calvin", @"Ross", @"Darren", @"Oscar", @"Drew", @"Maurice", @"Gerald", @"Alejandro", 
        @"Spencer", @"Hector", @"Ruben", @"Wayne", @"Brendan", @"Grant", @"Javier", @"Bruce", @"Roy", @"Dylan", @"Logan", @"Edwin", @"Omar", @"Brad", @"Reginald", @"Fernando", 
        @"Darrell", @"Sergio", @"Frederick", @"Julian", @"Jaime", @"Jermaine", @"Geoffrey", @"Levi", @"Terrance", @"Noah", @"Dominic", @"Rafael", @"Jerome", @"Pedro", @"Raul", 
        @"Eddie", @"Theodore", @"Neil", @"Tyrone", @"Edgar", @"Jessie", @"Ronnie", @"Marvin", @"Eduardo", @"Ivan", @"Jake", @"Ernest", @"Micah", @"Kurt", @"Terrence", @"Eugene", 
        @"Ramon", @"Dale", @"Tommy", @"Leonard", @"Ethan", @"Armando", @"Steve", @"Darryl", @"Bryce", @"Nicolas", @"Preston", @"Glenn", @"Alberto", @"Andres", @"Barry", @"Marco", 
        @"Kelly", @"Emmanuel", @"Bryant", @"Byron", @"Clifford", @"Melvin", @"Francis", @"Karl", @"Julio", @"Devon", @"Stanley", @"Jarrod", @"Harold", @"Cesar", @"Dwayne", @"Erick", 
        @"Tyson", @"Max", @"Cole", @"Abraham", @"Andy", @"Franklin", @"Damien", @"Shannon", @"Joey", @"Dean", @"Ralph", @"Cedric", @"Marshall", @"Terrell", @"Ray", @"Alfredo", 
        @"Arturo", @"Courtney", @"Warren", @"Orlando", @"Leon", @"Antoine", @"Enrique", @"Gilbert", @"Tristan", @"Elijah", @"Harry", @"Clint", @"Alvin", @"Alfred", @"Branden", 
        @"Earl", @"Clarence", @"Brady", @"Rene", @"Nickolas", @"Gerardo", @"Morgan", @"Demetrius", @"Kirk", @"Jamal", @"Darius", @"Beau", @"Kelvin", @"Lorenzo", @"Howard", @"Xavier", 
        @"Nelson", @"Wade", @"Trent", @"Marcos", @"Daryl", @"Colby", @"Dane", @"Isaiah", @"Johnathon", @"Ernesto", @"Salvador", @"Roderick", @"Stuart", @"Heath", @"Bernard", @"Chris", 
        @"Clifton", @"Quentin", @"Damon", @"Brock", @"Israel", @"Darnell", @"Angelo", @"Collin", @"Lamar", @"Landon", @"Trenton", @"Hunter", @"Norman", @"Lewis", @"Maxwell", 
        @"Damian", @"Tanner", @"Miles", @"Dallas", @"Leroy", @"Allan", @"Kenny", @"Bret", @"Mason", @"Charlie", @"Neal", @"Kendrick", @"Eli", @"Desmond", @"Gavin", @"Zachery", 
        @"Vernon", @"Simon", @"Rudy", @"Glen", @"Felix", @"Duane", @"Ashley", @"Rodolfo", @"Dwight", @"Lonnie", @"Julius", @"Pablo", @"Dominique", @"Terence", @"Alexis", @"Gordon", 
        @"Kent", @"Don", @"Zachariah", @"Quinton", @"Derick", @"Graham", @"Jamar", @"Rickey", @"Jayson", @"Jarrett", @"Marquis", @"Kurtis", @"Fredrick", @"Emanuel", @"Gustavo", 
        @"Deandre", @"Fred", @"Jarvis", @"Noel", @"Kendall", @"Elliott", @"Bradford", @"Rory", @"Chance", @"Abel", @"Nolan", @"Dana", @"Perry", @"Lloyd", @"Donovan", @"Alfonso", 
        @"Leo", @"Marlon", @"Malcolm", @"Josue", @"Dillon", @"Ben", @"Elias", @"Elliot", @"Herbert", @"Fabian", @"Kerry", @"Josiah", @"Dante", @"Rocky", @"Guillermo", @"Brenton", 
        @"Stephan", @"Dexter", @"Rick", @"Ismael", @"Felipe", @"Roland", @"Rolando", @"Jarred", @"Kory", @"Darin", @"Oliver", @"Saul", @"Cornelius", @"Pierre", @"Sam", @"Owen", 
        @"Gilberto", @"Clay", @"Stefan", @"Dusty", @"Carlton", @"Dominick", @"Harrison", @"Roman", @"Rogelio", @"Colton", @"Jamaal", @"Diego", @"Leslie", @"Freddie", @"Donnie", 
        @"Robin", @"Jeff", @"Rashad", @"Rusty", @"Toby", @"Milton", @"Hugo", @"Johnnie", @"Antwan", @"Tyrell", @"Blaine", @"Quincy", @"Frankie", @"Loren", @"Guy", @"Ty", @"Alonzo", 
        @"Gene", @"Jimmie", @"Esteban", @"Greg", @"Lester", @"Tracy", @"Nathanael", @"Darrin", @"Forrest", @"Mike", @"Floyd", @"Lamont", @"Chadwick", @"Skyler", @"Riley", @"Jody", 
        @"Jerrod", @"Weston", @"Trey", @"Salvatore", @"Zackary", @"Lionel", @"Dewayne", @"Giovanni", @"Sheldon", @"Sidney", @"Tomas", @"Gerard", @"Ramiro", @"Moses", @"Connor", 
        @"Jackie", @"Leonardo", @"Jackson", @"Brendon", @"Moises", @"Herman", @"Everett", @"Jarod", @"Kareem", @"Scotty", @"Ted", @"Kasey", @"Alec", @"Clark", @"Kody", @"Ariel", 
        @"Sterling", @"Cecil", @"Zane", @"Randolph", @"Jonah", @"Avery", @"Wilson", @"Reid", @"Bryon", @"Korey", @"Brooks", @"Reynaldo", @"Clyde", @"Sebastian", @"Ali", @"Josh", 
        @"Chester", @"Dan", @"Parker", @"Wyatt", @"Efrain", @"Reuben", @"Noe", @"Myron", @"Brennan", @"Chaz", @"Nick", @"Emilio", @"Conor", @"Aron", @"Guadalupe", @"Stewart", @"Sammy", 
        @"Santiago", @"Wendell", @"Jean", @"Dion", @"Zackery", @"Adan", @"Freddy", @"Arnold", @"Jess", @"Garry", @"Jim", @"Brice", @"Lyle", @"Kaleb", @"Rex", @"Myles", @"Keenan", 
        @"Deangelo", @"Robbie", @"Vicente", @"Randal", @"Alvaro", @"Joaquin", @"Solomon", @"Harvey", @"Thaddeus", @"Jordon", @"Anton", @"Erich", @"Will", @"Jonas", @"Benny", 
        @"Braden", @"Carson", @"Conrad", @"Deon", @"Amos", @"Harley", @"Sonny", @"Quintin", @"Ahmad", @"Raphael", @"Quinn", @"Dorian", @"Sherman", @"Dakota", @"Otis", @"Alton", 
        @"Erin", @"Reed", @"Ignacio", @"Garret", @"Jamison", @"Bryson", @"Blair", @"Barrett", @"Jovan", @"Jaron", @"Marcel", @"Markus", @"Leland", @"Ira", @"Rodrigo", @"Hugh", 
        @"Mauricio", @"Deshawn", @"Davis", @"Arron", @"Marty", @"Claude", @"Ashton", @"Jessica", @"Sylvester", @"Aubrey", @"Earnest", @"Ron", @"Winston", @"Edmund", @"Tom", @"Pete", 
        @"Morris", @"Nikolas", @"Nigel", @"Teddy", @"Waylon", @"Elvis", @"Cristian", @"Luther", @"Royce", @"Shea", @"Willis", @"Lukas", @"Damion", @"Gregg", @"Lane", @"Vance", @"Bo", 
        @"Hans", @"Brenden", @"Darrel", @"Jasper", @"Santos", @"Issac", @"Rico", @"Wallace", @"Amir", @"Agustin", @"Mickey", @"Bill", @"Wilfredo", @"Brant", @"Tory", @"Cary", 
        @"Tobias", @"Akeem", @"Shayne", @"Ezra", @"Virgil", @"Keegan", @"Kristian", @"Rudolph", @"Bennie", @"Jennifer", @"Heriberto", @"Carter", @"Mohammad", @"Marion", @"Adolfo", 
        @"Robby", @"Jerald", @"Jefferson", @"Matt", @"Shelby", @"Carey", @"Timmy", @"Ervin", @"Roosevelt", @"Isiah", @"Benito", @"Jed", @"Bennett", @"Jace", @"Tommie", @"Daren", 
        @"Elmer", @"Josef", @"Skylar", @"Whitney", @"Tucker", @"Carlo", @"Galen", @"Stacy", @"Prince", @"Cyrus", @"Ezekiel", @"Ellis", @"Dave", @"Liam", @"Moshe", @"Dalton", @"Coty", 
        @"Curt", @"Grady", @"Rhett", @"Jamil", @"Jeremie", @"Vaughn", @"Nestor", @"Titus", @"Abram", @"Reggie", @"Mikel", @"Paris", @"Kelsey", @"Malik", @"Van", @"Chauncey", @"Duncan", 
        @"Octavio", @"Jedidiah", @"Laurence", @"Kenton", @"Cale", @"Cortney", @"Aric", @"Asa", @"Donny", @"Devan", @"Aldo", @"Ahmed", @"Rocco", @"Bernardo", @"Osvaldo", @"Ulysses", 
        @"German", @"Jacques", @"Domingo", @"Antony", @"Cornell", @"Gregorio", @"Irvin", @"Louie", @"Fidel", @"Mack", @"Cruz", @"Westley", @"Alphonso", @"Gonzalo", @"Hassan", 
        @"Tyron", @"Jeffry", @"Chandler", @"Archie", @"Ari", @"Davin", @"Mohammed", @"Kirby", @"Shelton", @"Scottie", @"Dario", @"Raymundo", @"Edmond", @"Gino", @"Denny", @"Ken", 
        @"Junior", @"Willard", @"Coleman", @"Buddy", @"Griffin", @"Cullen", @"Wilbert", @"Silas", @"Andrea", @"Federico", @"Amanda", @"Michel", @"Dirk", @"Stacey", @"August", 
        @"Lincoln", @"Darwin", @"Kristoffer", @"Mackenzie", @"Monte", @"Corbin", @"Bart", @"Marlin", @"Rashawn", @"Isidro", @"Stevie", @"Raheem", @"Elvin", @"Rickie", @"Britton", 
        @"Brody", @"Theron", @"Jan", @"Emmett", @"Addison", @"Cordell", @"Leif", @"Andreas", @"Randell", @"Francesco", @"Rufus", @"Horace", @"Sarah", @"Marquise", @"Kris", 
        @"Cleveland", @"Scot", @"Chaim", @"Kameron", @"Isaias", @"Jakob", @"Garrick", @"Cassidy", @"Denver", @"Drake", @"Maximilian", @"Elizabeth", @"Eddy", @"Justine", @"Muhammad", 
        @"Erwin", @"Jade", @"Ronny", @"Lindsey", @"Tad", @"Irving", @"Ezequiel", @"Mohamed", @"Deonte", @"Eliseo", @"Brannon", @"Hank", @"Lynn", @"Ernie", @"Percy", @"Denis", 
        @"Stephanie", @"Delbert", @"Grayson", @"Cooper", @"Brandt", @"Hubert", @"Elton", @"Tylor", @"Ramsey", @"Jamey", @"Maria", @"Amit", @"Kai", @"Cliff", @"Edgardo", @"Tim", 
        @"Deven", @"Valentin", @"Keaton", @"Anderson", @"Rodger", @"Coby", @"Lowell", @"Al", @"Samson", @"Jayme", @"Vince", @"Eloy", @"Pierce", @"Lauren", @"Samir", @"Elisha", 
        @"Dewey", @"Schuyler", @"Eliezer", @"Braxton", @"Melissa", @"Chet", @"Kyler", @"Vito", @"Errol", @"Kim", @"Uriel", @"Cristobal", @"Hayden", @"Armand", @"Channing", 
        @"Giuseppe", @"Dedrick", @"Darian", @"Nicole", @"Jory", @"Jessica", @"Jennifer", @"Amanda", @"Ashley", @"Sarah", @"Stephanie", @"Melissa", @"Nicole", @"Elizabeth", 
        @"Heather", @"Tiffany", @"Michelle", @"Amber", @"Megan", @"Amy", @"Rachel", @"Kimberly", @"Christina", @"Lauren", @"Crystal", @"Brittany", @"Rebecca", @"Laura", @"Danielle", 
        @"Emily", @"Samantha", @"Angela", @"Erin", @"Kelly", @"Sara", @"Lisa", @"Katherine", @"Andrea", @"Jamie", @"Mary", @"Erica", @"Courtney", @"Kristen", @"Shannon", @"April", 
        @"Katie", @"Lindsey", @"Kristin", @"Lindsay", @"Christine", @"Alicia", @"Vanessa", @"Maria", @"Kathryn", @"Allison", @"Julie", @"Anna", @"Tara", @"Kayla", @"Natalie", 
        @"Victoria", @"Monica", @"Jacqueline", @"Holly", @"Kristina", @"Patricia", @"Cassandra", @"Brandy", @"Whitney", @"Chelsea", @"Brandi", @"Catherine", @"Cynthia", @"Kathleen", 
        @"Veronica", @"Leslie", @"Natasha", @"Krystal", @"Stacy", @"Diana", @"Erika", @"Dana", @"Jenna", @"Meghan", @"Carrie", @"Leah", @"Melanie", @"Brooke", @"Karen", @"Alexandra", 
        @"Valerie", @"Caitlin", @"Julia", @"Alyssa", @"Jasmine", @"Hannah", @"Stacey", @"Brittney", @"Susan", @"Margaret", @"Sandra", @"Candice", @"Latoya", @"Bethany", @"Misty", 
        @"Katrina", @"Tracy", @"Casey", @"Kelsey", @"Kara", @"Nichole", @"Alison", @"Heidi", @"Alexis", @"Molly", @"Tina", @"Pamela", @"Rachael", @"Nancy", @"Jillian", @"Candace", 
        @"Denise", @"Sabrina", @"Gina", @"Jill", @"Renee", @"Kendra", @"Morgan", @"Brenda", @"Monique", @"Teresa", @"Krista", @"Linda", @"Miranda", @"Robin", @"Dawn", @"Kristy", 
        @"Theresa", @"Tanya", @"Wendy", @"Melinda", @"Joanna", @"Anne", @"Felicia", @"Desiree", @"Jaclyn", @"Alisha", @"Lori", @"Tamara", @"Marissa", @"Kelli", @"Lacey", @"Abigail", 
        @"Christy", @"Jenny", @"Tabitha", @"Colleen", @"Meredith", @"Barbara", @"Angelica", @"Carolyn", @"Rebekah", @"Ebony", @"Deanna", @"Tonya", @"Caroline", @"Kristi", @"Kari", 
        @"Michele", @"Brianna", @"Bridget", @"Angel", @"Marie", @"Sharon", @"Tasha", @"Sheena", @"Meagan", @"Jaime", @"Cindy", @"Priscilla", @"Ann", @"Ashlee", @"Stefanie", @"Cassie", 
        @"Adrienne", @"Tammy", @"Ana", @"Beth", @"Dominique", @"Latasha", @"Cristina", @"Mallory", @"Virginia", @"Deborah", @"Audrey", @"Katelyn", @"Regina", @"Carla", @"Cheryl", 
        @"Olivia", @"Autumn", @"Jordan", @"Claudia", @"Nina", @"Taylor", @"Kristine", @"Kate", @"Janet", @"Jacquelyn", @"Cara", @"Aimee", @"Mandy", @"Donna", @"Martha", @"Suzanne", 
        @"Shawna", @"Trisha", @"Haley", @"Mindy", @"Carmen", @"Adriana", @"Janelle", @"Carly", @"Bianca", @"Kaitlin", @"Summer", @"Bonnie", @"Toni", @"Abby", @"Robyn", @"Grace", 
        @"Joy", @"Alexandria", @"Jodi", @"Gabrielle", @"Yolanda", @"Kellie", @"Diane", @"Ruth", @"Mayra", @"Paula", @"Lydia", @"Jessie", @"Evelyn", @"Briana", @"Krystle", @"Naomi", 
        @"Claire", @"Sophia", @"Rosa", @"Kaitlyn", @"Gloria", @"Nikki", @"Melody", @"Marisa", @"Paige", @"Emma", @"Ellen", @"Shanna", @"Britney", @"Shana", @"Jeanette", @"Ashleigh", 
        @"Debra", @"Rose", @"Kelley", @"Raquel", @"Amelia", @"Randi", @"Kasey", @"Sasha", @"Christie", @"Hillary", @"Sheila", @"Sonia", @"Keri", @"Karla", @"Sylvia", @"Daisy", 
        @"Shelly", @"Justine", @"Roxanne", @"Rachelle", @"Charlene", @"Sierra", @"Carol", @"Jocelyn", @"Esther", @"Chelsey", @"Stacie", @"Kirsten", @"Christa", @"Anita", @"Tia", 
        @"Sherry", @"Rhonda", @"Kerri", @"Savannah", @"Yvonne", @"Frances", @"Shauna", @"Traci", @"Charlotte", @"Leigh", @"Sonya", @"Lacy", @"Helen", @"Tracey", @"Karina", @"Hilary", 
        @"Laurie", @"Annie", @"Yesenia", @"Charity", @"Alissa", @"Angelina", @"Johanna", @"Leticia", @"Kristie", @"Brianne", @"Tamika", @"Shelby", @"Katharine", @"Gabriela", @"Eva", 
        @"Elise", @"Terri", @"Yvette", @"Miriam", @"Hope", @"Carissa", @"Latisha", @"Kerry", @"Maggie", @"Janice", @"Elisabeth", @"Jane", @"Breanna", @"Alice", @"Rochelle", 
        @"Tabatha", @"Jana", @"Allyson", @"Dorothy", @"Maureen", @"Elaine", @"Annette", @"Tricia", @"Chasity", @"Irene", @"Cortney", @"Staci", @"Jade", @"Kathy", @"Cecilia", 
        @"Camille", @"Antoinette", @"Alana", @"Keisha", @"Shelley", @"Sandy", @"Tanisha", @"Aubrey", @"Lynn", @"Elisa", @"Faith", @"Juanita", @"Lorena", @"Destiny", @"Jami", 
        @"Brandie", @"Jennie", @"Lesley", @"Clarissa", @"Bobbie", @"Ariel", @"Tessa", @"Ruby", @"Elena", @"Ericka", @"Ryan", @"Amie", @"Rita", @"Sally", @"Hayley", @"Connie", 
        @"Guadalupe", @"Jackie", @"Patrice", @"Jasmin", @"Becky", @"Katy", @"Joyce", @"Marquita", @"Lyndsey", @"Judith", @"Leanne", @"Taryn", @"Constance", @"Latonya", @"Eileen", 
        @"Alma", @"Mia", @"Gretchen", @"Angie", @"Jenifer", @"Tiara", @"Chrystal", @"Marilyn", @"Marisol", @"Shayla", @"Alyson", @"Lakeisha", @"Norma", @"Maribel", @"Alejandra", 
        @"Nadia", @"Nora", @"Madeline", @"Kira", @"Kylie", @"Joanne", @"Lara", @"Lillian", @"Beverly", @"Belinda", @"Meaghan", @"Christin", @"Celeste", @"Jolene", @"Serena", @"Alisa", 
        @"Michael", @"Devon", @"Darlene", @"Hollie", @"Corinne", @"Betty", @"Christian", @"Shirley", @"Audra", @"Callie", @"Sherri", @"Jody", @"Tameka", @"Rosemary", @"Trista", 
        @"Isabel", @"Tiffani", @"Laurel", @"Bridgette", @"Lakisha", @"Judy", @"Jean", @"Elisha", @"Anastasia", @"Larissa", @"Tatiana", @"Alexa", @"Esmeralda", @"Bobbi", @"Marlene", 
        @"Christen", @"Genevieve", @"Carolina", @"Iris", @"Josephine", @"Lucy", @"Ariana", @"Terra", @"Michaela", @"Jayme", @"Julianne", @"Chantel", @"Mackenzie", @"Noelle", 
        @"Blanca", @"Lena", @"Janine", @"Sheri", @"Sydney", @"Mercedes", @"Alaina", @"Blair", @"Ginger", @"Brittani", @"Kristal", @"Leann", @"Billie", @"Margarita", @"Dianna", 
        @"Chandra", @"Caitlyn", @"Joann", @"Jodie", @"Aisha", @"Tania", @"Tracie", @"Chanel", @"Kendall", @"Ciara", @"Elyse", @"Brenna", @"Joni", @"Tierra", @"Marina", @"Lora", 
        @"Vivian", @"Daniela", @"Lorraine", @"Ashlie", @"Mandi", @"Shayna", @"Jena", @"Francesca", @"Kyla", @"Susana", @"Betsy", @"Jacklyn", @"Chelsie", @"Juliana", @"Raven", 
        @"Liliana", @"Teri", @"Lea", @"Tiana", @"Melisa", @"Simone", @"Arielle", @"Kassandra", @"Natalia", @"Gwendolyn", @"Bailey", @"Shaina", @"Devin", @"Karissa", @"Kim", 
        @"Kimberley", @"Adrian", @"Lee", @"Madison", @"Christi", @"Jeannette", @"Angelique", @"Breanne", @"Abbey", @"Asia", @"Leanna", @"Adrianne", @"Arlene", @"Cathy", 
        @"Christopher", @"Clara", @"Shari", @"Dena", @"Kacie", @"Mariah", @"Marcia", @"Precious", @"Trina", @"Lynette", @"Mollie", @"Jaimie", @"Marsha", @"India", @"Cierra", 
        @"Lashonda", @"Cherie", @"Lana", @"Sade", @"Celia", @"Luz", @"Kenya", @"Tori", @"Debbie", @"Maritza", @"Fallon", @"Racheal", @"Ashton", @"Hailey", @"Lyndsay", @"Selena", 
        @"Antonia", @"Lucia", @"Rocio", @"Chloe", @"Dina", @"Nadine", @"Adrianna", @"Joan", @"Dayna", @"Kaylee", @"Bernadette", @"Marianne", @"Roberta", @"Tera", @"Elissa", 
        @"Loretta", @"Rhiannon", @"Darcy", @"Janna", @"Silvia", @"Sonja", @"Araceli", @"Shantel", @"Cassidy", @"Rosanna", @"Alecia", @"Janette", @"Edith", @"Myra", @"Catrina", 
        @"Sadie", @"Talia", @"Corey", @"Jesse", @"Ivy", @"Peggy", @"Janie", @"Liza", @"Deidre", @"Cari", @"Corina", @"Octavia", @"Jeanne", @"Cheri", @"Jeannie", @"Candy", @"Maya", 
        @"Beatriz", @"Cori", @"Athena", @"Nicolette", @"Alanna", @"Maricela", @"Marjorie", @"Kimberlee", @"Dara", @"Cristal", @"Justina", @"Wanda", @"Georgia", @"Kiara", @"Janae", 
        @"Maryann", @"Desirae", @"Noemi", @"Marcella", @"Leeann", @"Eleanor", @"Martina", @"Marla", @"Jazmin", @"Deana", @"Eliza", @"Beatrice", @"Nikita", @"Shanika", @"Tami", 
        @"Deidra", @"Daphne", @"Maura", @"Lily", @"Kayleigh", @"Olga", @"Selina", @"Loren", @"Kacey", @"Emilie", @"Penny", @"Irma", @"Janel", @"Mara", @"Sofia", @"Carina", @"James", 
        @"Laci", @"Valarie", @"Matthew", @"Joshua", @"Kala", @"Shawn", @"Josie", @"Kali", @"Daniel", @"Alesha", @"Gladys", @"Daniella", @"Noel", @"Princess", @"Ingrid", @"Susanna", 
        @"Celina", @"Marisela", @"Pauline", @"Maegan", @"Hanna", @"Doris", @"Lizette", @"Abbie", @"Andria", @"Glenda", @"Marlena", @"Julianna", @"Kyle", @"Fatima", @"Karin", @"David", 
        @"Gillian", @"Dora", @"Chastity", @"Christal", @"Aileen", @"Renae", @"Ladonna", @"Geneva", @"Rena", @"Marcy", @"Cheyenne", @"Malinda", @"Mariana", @"Tanesha", @"Lakeshia", 
        @"Yadira", @"Ciera", @"Griselda", @"Aurora", @"Cora", @"Keshia", @"Demetria", @"Delia", @"Kourtney", @"Ramona", @"Joelle", @"Jeanine", @"Vicki", @"Tarah", @"Alycia", 
        @"Monika", @"Kathrine", @"Marcie", @"Kyra", @"Cameron", @"Sheree", @"Kia", @"Brook", @"Leila", @"Chantelle", @"Annmarie", @"Robert", @"Elsa", @"Vicky", @"Cory", @"Charmaine", 
        @"Justin", @"Misti", @"Kori", @"Deirdre", @"Viviana", @"Rikki", @"Kylee", @"Lynda", @"Roxana", @"Helena", @"John", @"Stevie", @"Edna", @"Linsey", @"Rene", @"Perla", @"Marian", 
        @"Sheryl", @"Dolores", @"Roxanna", @"Lynsey", @"Jessi", @"Kati", @"Richelle", @"Gabriella", @"Valencia", @"Kelsie", @"Savanna", @"Jazmine", @"Danica", @"Alysha", @"Lucinda", 
        @"Tamra", @"Marci", @"Rosalinda", @"Joseph", @"Lourdes", @"Sherrie", @"Brandon", @"Cecelia", @"Mari", @"Emilee", @"Rosemarie", @"Kiley", @"Nikole", @"Reyna", @"Candi", 
        @"Jenelle", @"Jeanna", @"Stephany", @"Georgina", @"Clare", @"Siobhan", @"Gail", @"Jamila", @"Caryn", @"Shanta", @"Alysia", @"Tonia", @"Alina", @"Alexia", @"Krystina", @"Cody", 
        @"Kandace", @"Chantal", @"Louise", @"Zoe", @"Sondra", @"Delilah", @"Francine", @"Candis", @"Hallie", @"Jason", @"Katlyn", @"Nathalie", @"Mckenzie", @"Stacia", @"Jada", 
        @"William", @"Salina", @"Micah", @"Carley", @"Alyse", @"Brynn", @"Juana", @"Jo", @"Giselle", @"Kristian", @"Johnna", @"Wendi", @"Lisette", @"Terry", @"Rebeca", @"Ami", 
        @"Graciela", @"Cherish", @"Latanya", @"Paris", @"Shanice", @"Portia", @"Cathleen", @"Carey", @"Corrie", @"Katelin", @"Tess", @"Marion", @"Darla", @"Hilda", @"Shea", 
        @"Kirstin", @"Tisha", @"Tammie", @"Keely", @"Katelynn", @"Eunice", @"Sophie", @"Kaila", @"Stella", @"Jonathan", @"Marta", @"Tyler", @"Rosalie", @"Magdalena", @"Andrew", 
        @"Jeana", @"Colette", @"June", @"Corrine", @"Paola", @"Liana", @"Susie", @"Margo", @"Karrie", @"Kaley", @"Iesha", @"Jeri", @"Anthony", @"Arianna", @"Kaleigh", @"Valeria", 
        @"Deena", @"Kerrie", @"Katheryn", @"Brandee", @"Diamond", @"Pearl", @"Ali", @"Lia", @"Lawanda", @"Gena", @"Angelia", @"Jessika", @"Allie", @"Sue", @"Yasmin", @"Micaela", 
        @"Tanika", @"Kisha", @"Breann", @"Melina", @"Quiana", @"Mai", @"Leilani", @"Mariel", @"Brittny", @"Bertha", @"Ronda", @"Charissa", @"Janessa", @"Vickie", @"Annemarie", 
        @"Ashlyn", @"Lindy", @"Jenni", @"Juliet", @"Krysten"
    ];

    
    return [randomNames objectAtIndex:([self randomUInt32] % randomNames.count)];
}

+ (uint32_t)randomUInt32
{
    uint8_t randomBytes[4];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused"
    SecRandomCopyBytes(kSecRandomDefault, 4, randomBytes); // gotta have priorities. I'm not going to put an insecure RNG in my throwaway random-stuff class.
#pragma clang diagnostic pop
    return (uint32_t) *randomBytes;
}

@end
