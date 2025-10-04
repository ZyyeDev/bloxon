import json
import requests
import time
import random
from datetime import datetime

class DatasetExpander:
    def __init__(self):
        self.dataset_file = "dataset.json"
        
    def get_reddit_data(self, subreddits, limit=50):
        all_texts = []
        for subreddit in subreddits:
            try:
                headers = {'User-Agent': 'DataCollector/1.0'}
                url = f'https://www.reddit.com/r/{subreddit}/hot.json?limit={limit}'
                response = requests.get(url, headers=headers)
                
                if response.status_code == 200:
                    data = response.json()
                    for post in data['data']['children']:
                        post_data = post['data']
                        if post_data.get('selftext') and len(post_data['selftext']) > 10:
                            all_texts.append(post_data['selftext'])
                        if post_data.get('title') and len(post_data['title']) > 10:
                            all_texts.append(post_data['title'])
                
                time.sleep(2)
            except:
                continue
        
        return all_texts

    def get_keyword_labels(self, text):
        text_lower = text.lower()
        
        sexual_words = ['sex', 'porn', 'nude', 'naked', 'sexy', 'boobs', 'dick', 'pussy', 'fuck', 'cum', 'orgasm', 'masturbate', 'horny']
        hate_words = ['hate', 'nazi', 'racist', 'nigger', 'faggot', 'retard', 'kill yourself', 'kys', 'die', 'cancer', 'trash human']
        violence_words = ['kill', 'murder', 'death', 'blood', 'stab', 'shoot', 'gun', 'knife', 'bomb', 'explosion', 'torture']
        harassment_words = ['noob', 'trash', 'garbage', 'loser', 'pathetic', 'worthless', 'stupid', 'idiot', 'moron', 'ez', 'get rekt', 'uninstall']
        self_harm_words = ['suicide', 'self harm', 'cut myself', 'end my life', 'want to die', 'kill myself']
        
        gaming_toxic = ['ez clap', 'git gud', 'skill issue', 'touch grass', 'go outside', 'delete game', 'uninstall', 'hardstuck', 'boosted']
        
        return {
            'S': 1 if any(word in text_lower for word in sexual_words) else 0,
            'H': 1 if any(word in text_lower for word in hate_words) else 0,
            'V': 1 if any(word in text_lower for word in violence_words) else 0,
            'HR': 1 if any(word in text_lower for word in harassment_words + gaming_toxic) else 0,
            'SH': 1 if any(word in text_lower for word in self_harm_words) else 0,
            'S3': 1 if any(word in text_lower for word in ['child', 'kid', 'minor']) and any(word in text_lower for word in sexual_words) else 0,
            'H2': 1 if any(word in text_lower for word in hate_words) and any(word in text_lower for word in violence_words) else 0,
            'V2': 1 if any(word in text_lower for word in ['gore', 'brutal', 'graphic', 'dismember', 'decapitate']) else 0
        }

    def generate_toxic_samples(self):
        toxic_templates = [
            "{} is trash at this game",
            "ez win {}, get good",
            "{} should uninstall",
            "imagine being as bad as {}",
            "{} is carried by team",
            "1v1 me {} you won't",
            "{} has skill issue",
            "go touch grass {}",
            "{} delete the game",
            "hardstuck {} player",
            "boosted {} account",
            "{} git gud noob",
            "ez clap {} diff",
            "{} go play minecraft",
            "reported {} for griefing"
        ]
        
        placeholders = ['noob', 'kid', 'player', 'teammate', 'enemy', 'scrub']
        
        samples = []
        for template in toxic_templates:
            for placeholder in placeholders:
                samples.append(template.format(placeholder))
        
        clean_samples = [
            "good game everyone",
            "well played team",
            "nice shot",
            "thanks for the help",
            "gg wp",
            "that was fun",
            "great teamwork",
            "close game",
            "you played well",
            "good luck next game",
            "sorry for the mistake",
            "my bad team",
            "let's try again",
            "almost had it",
            "we can win this"
        ]
        
        return samples + clean_samples

    def load_existing_dataset(self):
        try:
            with open(self.dataset_file, 'r') as f:
                return [json.loads(line) for line in f]
        except:
            return []

    def save_to_dataset(self, new_samples):
        existing_prompts = set()
        existing_data = self.load_existing_dataset()
        
        for item in existing_data:
            existing_prompts.add(item['prompt'])
        
        unique_samples = []
        for sample in new_samples:
            if sample['prompt'] not in existing_prompts and len(sample['prompt']) > 5:
                unique_samples.append(sample)
                existing_prompts.add(sample['prompt'])
        
        with open(self.dataset_file, 'a') as f:
            for sample in unique_samples:
                f.write(json.dumps(sample) + '\n')
        
        return len(unique_samples)

    def run(self):
        print("Starting data collection...")
        
        all_new_samples = []
        
        gaming_subreddits = [
            'gaming', 'pcmasterrace', 'leagueoflegends', 'minecraft',
            'valorant', 'csgo', 'dota2', 'overwatch', 'apexlegends',
            'roblox', 'fortnite', 'callofduty'
        ]
        
        reddit_texts = self.get_reddit_data(gaming_subreddits, limit=30)
        print(f"Got {len(reddit_texts)} texts from Reddit")
        
        gaming_variants = self.generate_toxic_samples()
        print(f"Generated {len(gaming_variants)} gaming samples")
        
        all_texts = reddit_texts + gaming_variants
        
        for i, text in enumerate(all_texts):
            if i % 10 == 0:
                print(f"Processing {i}/{len(all_texts)}")
            
            labels = self.get_keyword_labels(text)
            
            sample = {
                'prompt': text.strip(),
                **labels
            }
            all_new_samples.append(sample)
        
        added_count = self.save_to_dataset(all_new_samples)
        print(f"Added {added_count} new unique samples to dataset.json")

if __name__ == "__main__":
    expander = DatasetExpander()
    expander.run()