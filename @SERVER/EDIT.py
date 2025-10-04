import tkinter as tk
from tkinter import ttk, messagebox, scrolledtext
import sqlite3
import json
import os
import time

DB_FILE = os.path.join("server_data", "server.db")
PLAYER_DATA_FILE = os.path.join("server_data", "player_data.dat")

class DatabaseEditor:
    def __init__(self, root):
        self.root = root
        self.root.title("Database Editor")
        self.root.geometry("1200x700")
        self.root.configure(bg="#f0f0f0")
        
        self.player_data = {}
        self.load_player_data()
        
        self.create_widgets()
        self.refresh_all()
    
    def load_player_data(self):
        try:
            if os.path.exists(PLAYER_DATA_FILE):
                with open(PLAYER_DATA_FILE, "r") as f:
                    self.player_data = json.load(f)
        except:
            self.player_data = {}
    
    def save_player_data(self):
        try:
            os.makedirs("server_data", exist_ok=True)
            with open(PLAYER_DATA_FILE, "w") as f:
                json.dump(self.player_data, f, indent=2)
            messagebox.showinfo("Success", "Player data saved!")
            return True
        except Exception as e:
            messagebox.showerror("Error", f"Failed to save: {e}")
            return False
    
    def create_widgets(self):
        notebook = ttk.Notebook(self.root)
        notebook.pack(fill=tk.BOTH, expand=True, padx=10, pady=10)
        
        self.create_accounts_tab(notebook)
        self.create_player_data_tab(notebook)
        self.create_datastores_tab(notebook)
        self.create_tokens_tab(notebook)
    
    def create_accounts_tab(self, notebook):
        frame = ttk.Frame(notebook)
        notebook.add(frame, text="Accounts")
        
        btn_frame = ttk.Frame(frame)
        btn_frame.pack(fill=tk.X, padx=5, pady=5)
        
        ttk.Button(btn_frame, text="Refresh", command=self.refresh_accounts).pack(side=tk.LEFT, padx=5)
        ttk.Button(btn_frame, text="Delete Selected", command=self.delete_account).pack(side=tk.LEFT, padx=5)
        
        columns = ("username", "user_id", "gender", "created")
        self.accounts_tree = ttk.Treeview(frame, columns=columns, show="headings", height=20)
        
        self.accounts_tree.heading("username", text="Username")
        self.accounts_tree.heading("user_id", text="User ID")
        self.accounts_tree.heading("gender", text="Gender")
        self.accounts_tree.heading("created", text="Created")
        
        self.accounts_tree.column("username", width=200)
        self.accounts_tree.column("user_id", width=100)
        self.accounts_tree.column("gender", width=100)
        self.accounts_tree.column("created", width=200)
        
        scrollbar = ttk.Scrollbar(frame, orient=tk.VERTICAL, command=self.accounts_tree.yview)
        self.accounts_tree.configure(yscrollcommand=scrollbar.set)
        
        self.accounts_tree.pack(side=tk.LEFT, fill=tk.BOTH, expand=True, padx=5, pady=5)
        scrollbar.pack(side=tk.RIGHT, fill=tk.Y)
    
    def create_player_data_tab(self, notebook):
        frame = ttk.Frame(notebook)
        notebook.add(frame, text="Player Data")
        
        top_frame = ttk.Frame(frame)
        top_frame.pack(fill=tk.X, padx=5, pady=5)
        
        ttk.Label(top_frame, text="User ID:").pack(side=tk.LEFT, padx=5)
        self.player_id_var = tk.StringVar()
        ttk.Entry(top_frame, textvariable=self.player_id_var, width=15).pack(side=tk.LEFT, padx=5)
        ttk.Button(top_frame, text="Load", command=self.load_player).pack(side=tk.LEFT, padx=5)
        ttk.Button(top_frame, text="Save", command=self.save_player).pack(side=tk.LEFT, padx=5)
        ttk.Button(top_frame, text="Refresh List", command=self.refresh_player_list).pack(side=tk.LEFT, padx=5)
        
        paned = ttk.PanedWindow(frame, orient=tk.HORIZONTAL)
        paned.pack(fill=tk.BOTH, expand=True, padx=5, pady=5)
        
        left_frame = ttk.Frame(paned)
        paned.add(left_frame, weight=1)
        
        ttk.Label(left_frame, text="Players:").pack(anchor=tk.W, padx=5, pady=5)
        self.player_listbox = tk.Listbox(left_frame)
        self.player_listbox.pack(fill=tk.BOTH, expand=True, padx=5, pady=5)
        self.player_listbox.bind("<<ListboxSelect>>", self.on_player_select)
        
        right_frame = ttk.Frame(paned)
        paned.add(right_frame, weight=3)
        
        ttk.Label(right_frame, text="Player Data (JSON):").pack(anchor=tk.W, padx=5, pady=5)
        self.player_text = scrolledtext.ScrolledText(right_frame, width=60, height=30)
        self.player_text.pack(fill=tk.BOTH, expand=True, padx=5, pady=5)
    
    def create_datastores_tab(self, notebook):
        frame = ttk.Frame(notebook)
        notebook.add(frame, text="Datastores")
        
        btn_frame = ttk.Frame(frame)
        btn_frame.pack(fill=tk.X, padx=5, pady=5)
        
        ttk.Button(btn_frame, text="Refresh", command=self.refresh_datastores).pack(side=tk.LEFT, padx=5)
        ttk.Button(btn_frame, text="Edit Selected", command=self.edit_datastore).pack(side=tk.LEFT, padx=5)
        ttk.Button(btn_frame, text="Delete Selected", command=self.delete_datastore).pack(side=tk.LEFT, padx=5)
        
        columns = ("key", "value", "timestamp")
        self.datastores_tree = ttk.Treeview(frame, columns=columns, show="headings", height=20)
        
        self.datastores_tree.heading("key", text="Key")
        self.datastores_tree.heading("value", text="Value")
        self.datastores_tree.heading("timestamp", text="Timestamp")
        
        self.datastores_tree.column("key", width=300)
        self.datastores_tree.column("value", width=400)
        self.datastores_tree.column("timestamp", width=200)
        
        scrollbar = ttk.Scrollbar(frame, orient=tk.VERTICAL, command=self.datastores_tree.yview)
        self.datastores_tree.configure(yscrollcommand=scrollbar.set)
        
        self.datastores_tree.pack(side=tk.LEFT, fill=tk.BOTH, expand=True, padx=5, pady=5)
        scrollbar.pack(side=tk.RIGHT, fill=tk.Y)
    
    def create_tokens_tab(self, notebook):
        frame = ttk.Frame(notebook)
        notebook.add(frame, text="Tokens")
        
        btn_frame = ttk.Frame(frame)
        btn_frame.pack(fill=tk.X, padx=5, pady=5)
        
        ttk.Button(btn_frame, text="Refresh", command=self.refresh_tokens).pack(side=tk.LEFT, padx=5)
        ttk.Button(btn_frame, text="Delete Selected", command=self.delete_token).pack(side=tk.LEFT, padx=5)
        
        columns = ("token", "username", "created")
        self.tokens_tree = ttk.Treeview(frame, columns=columns, show="headings", height=20)
        
        self.tokens_tree.heading("token", text="Token")
        self.tokens_tree.heading("username", text="Username")
        self.tokens_tree.heading("created", text="Created")
        
        self.tokens_tree.column("token", width=400)
        self.tokens_tree.column("username", width=200)
        self.tokens_tree.column("created", width=200)
        
        scrollbar = ttk.Scrollbar(frame, orient=tk.VERTICAL, command=self.tokens_tree.yview)
        self.tokens_tree.configure(yscrollcommand=scrollbar.set)
        
        self.tokens_tree.pack(side=tk.LEFT, fill=tk.BOTH, expand=True, padx=5, pady=5)
        scrollbar.pack(side=tk.RIGHT, fill=tk.Y)
    
    def refresh_all(self):
        self.refresh_accounts()
        self.refresh_player_list()
        self.refresh_datastores()
        self.refresh_tokens()
    
    def refresh_accounts(self):
        for item in self.accounts_tree.get_children():
            self.accounts_tree.delete(item)
        
        try:
            conn = sqlite3.connect(DB_FILE)
            cursor = conn.cursor()
            cursor.execute("SELECT username, user_id, gender, created FROM accounts")
            for row in cursor.fetchall():
                self.accounts_tree.insert("", tk.END, values=row)
            conn.close()
        except Exception as e:
            messagebox.showerror("Error", f"Failed to load accounts: {e}")
    
    def refresh_player_list(self):
        self.player_listbox.delete(0, tk.END)
        self.load_player_data()
        for user_id in sorted(self.player_data.keys()):
            username = self.player_data[user_id].get("username", "Unknown")
            self.player_listbox.insert(tk.END, f"ID {user_id}: {username}")
    
    def refresh_datastores(self):
        for item in self.datastores_tree.get_children():
            self.datastores_tree.delete(item)
        
        try:
            conn = sqlite3.connect(DB_FILE)
            cursor = conn.cursor()
            cursor.execute("SELECT key, value, timestamp FROM datastores")
            for row in cursor.fetchall():
                value_preview = str(row[1])[:100]
                self.datastores_tree.insert("", tk.END, values=(row[0], value_preview, row[2]))
            conn.close()
        except Exception as e:
            messagebox.showerror("Error", f"Failed to load datastores: {e}")
    
    def refresh_tokens(self):
        for item in self.tokens_tree.get_children():
            self.tokens_tree.delete(item)
        
        try:
            conn = sqlite3.connect(DB_FILE)
            cursor = conn.cursor()
            cursor.execute("SELECT token, username, created FROM tokens")
            for row in cursor.fetchall():
                self.tokens_tree.insert("", tk.END, values=row)
            conn.close()
        except Exception as e:
            messagebox.showerror("Error", f"Failed to load tokens: {e}")
    
    def delete_account(self):
        selected = self.accounts_tree.selection()
        if not selected:
            messagebox.showwarning("Warning", "No account selected")
            return
        
        item = self.accounts_tree.item(selected[0])
        username = item["values"][0]
        
        if messagebox.askyesno("Confirm", f"Delete account '{username}'?"):
            try:
                conn = sqlite3.connect(DB_FILE)
                cursor = conn.cursor()
                cursor.execute("DELETE FROM accounts WHERE username = ?", (username,))
                conn.commit()
                conn.close()
                self.refresh_accounts()
                messagebox.showinfo("Success", "Account deleted")
            except Exception as e:
                messagebox.showerror("Error", f"Failed to delete: {e}")
    
    def on_player_select(self, event):
        selection = self.player_listbox.curselection()
        if selection:
            text = self.player_listbox.get(selection[0])
            user_id = text.split(":")[0].replace("ID ", "").strip()
            self.player_id_var.set(user_id)
            self.load_player()
    
    def load_player(self):
        user_id = self.player_id_var.get().strip()
        if not user_id:
            messagebox.showwarning("Warning", "Enter a user ID")
            return
        
        self.load_player_data()
        if user_id in self.player_data:
            data = json.dumps(self.player_data[user_id], indent=2)
            self.player_text.delete(1.0, tk.END)
            self.player_text.insert(1.0, data)
        else:
            messagebox.showwarning("Warning", f"No data for user ID {user_id}")
    
    def save_player(self):
        user_id = self.player_id_var.get().strip()
        if not user_id:
            messagebox.showwarning("Warning", "Enter a user ID")
            return
        
        try:
            data = self.player_text.get(1.0, tk.END)
            player_data = json.loads(data)
            self.player_data[user_id] = player_data
            
            if self.save_player_data():
                self.refresh_player_list()
        except json.JSONDecodeError as e:
            messagebox.showerror("Error", f"Invalid JSON: {e}")
    
    def edit_datastore(self):
        selected = self.datastores_tree.selection()
        if not selected:
            messagebox.showwarning("Warning", "No datastore selected")
            return
        
        item = self.datastores_tree.item(selected[0])
        key = item["values"][0]
        
        try:
            conn = sqlite3.connect(DB_FILE)
            cursor = conn.cursor()
            cursor.execute("SELECT value FROM datastores WHERE key = ?", (key,))
            result = cursor.fetchone()
            conn.close()
            
            if result:
                edit_window = tk.Toplevel(self.root)
                edit_window.title(f"Edit Datastore: {key}")
                edit_window.geometry("700x500")
                
                ttk.Label(edit_window, text=f"Key: {key}", font=('TkDefaultFont', 10, 'bold')).pack(padx=10, pady=10)
                
                text = scrolledtext.ScrolledText(edit_window, width=80, height=25)
                text.pack(padx=10, pady=10, fill=tk.BOTH, expand=True)
                text.insert(1.0, result[0])
                
                def save_edit():
                    new_value = text.get(1.0, tk.END).strip()
                    try:
                        conn = sqlite3.connect(DB_FILE)
                        cursor = conn.cursor()
                        cursor.execute("UPDATE datastores SET value = ?, timestamp = ? WHERE key = ?", 
                                     (new_value, time.time(), key))
                        conn.commit()
                        conn.close()
                        self.refresh_datastores()
                        edit_window.destroy()
                        messagebox.showinfo("Success", "Datastore updated")
                    except Exception as e:
                        messagebox.showerror("Error", f"Failed to save: {e}")
                
                btn_frame = ttk.Frame(edit_window)
                btn_frame.pack(pady=10)
                
                ttk.Button(btn_frame, text="Save", command=save_edit).pack(side=tk.LEFT, padx=5)
                ttk.Button(btn_frame, text="Cancel", command=edit_window.destroy).pack(side=tk.LEFT, padx=5)
        
        except Exception as e:
            messagebox.showerror("Error", f"Failed to load datastore: {e}")
    
    def delete_datastore(self):
        selected = self.datastores_tree.selection()
        if not selected:
            messagebox.showwarning("Warning", "No datastore selected")
            return
        
        item = self.datastores_tree.item(selected[0])
        key = item["values"][0]
        
        if messagebox.askyesno("Confirm", f"Delete datastore '{key}'?"):
            try:
                conn = sqlite3.connect(DB_FILE)
                cursor = conn.cursor()
                cursor.execute("DELETE FROM datastores WHERE key = ?", (key,))
                conn.commit()
                conn.close()
                self.refresh_datastores()
                messagebox.showinfo("Success", "Datastore deleted")
            except Exception as e:
                messagebox.showerror("Error", f"Failed to delete: {e}")
    
    def delete_token(self):
        selected = self.tokens_tree.selection()
        if not selected:
            messagebox.showwarning("Warning", "No token selected")
            return
        
        item = self.tokens_tree.item(selected[0])
        token = item["values"][0]
        
        if messagebox.askyesno("Confirm", "Delete selected token?"):
            try:
                conn = sqlite3.connect(DB_FILE)
                cursor = conn.cursor()
                cursor.execute("DELETE FROM tokens WHERE token = ?", (token,))
                conn.commit()
                conn.close()
                self.refresh_tokens()
                messagebox.showinfo("Success", "Token deleted")
            except Exception as e:
                messagebox.showerror("Error", f"Failed to delete: {e}")

if __name__ == "__main__":
    root = tk.Tk()
    app = DatabaseEditor(root)
    root.mainloop()