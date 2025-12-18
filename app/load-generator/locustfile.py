"""
Locust load testing for MSP clients
Simulates different traffic patterns per client
"""
from locust import HttpUser, task, between, constant
import random


class ClienteAUser(HttpUser):
    """
    E-commerce user simulation
    Traffic pattern: Moderate with occasional spikes
    """
    wait_time = between(1, 3)
    host = "http://cliente-a.msp-demo.local"
    
    @task(3)
    def list_products(self):
        """Browse products (most common action)"""
        self.client.get("/api/items")
    
    @task(2)
    def view_product(self):
        """View product details"""
        item_id = random.randint(1, 100)
        self.client.get(f"/api/items/{item_id}")
    
    @task(1)
    def create_order(self):
        """Create order (less frequent)"""
        self.client.post("/api/items", json={
            "name": f"Product {random.randint(1, 1000)}",
            "value": random.uniform(10.0, 500.0),
            "category": random.choice(["electronics", "clothing", "books"])
        })


class ClienteBUser(HttpUser):
    """
    Fintech user simulation
    Traffic pattern: Constant high load with unpredictable spikes
    """
    wait_time = constant(0.5)  # High frequency
    host = "http://cliente-b.msp-demo.local"
    
    @task(5)
    def create_transaction(self):
        """Process transaction (primary operation)"""
        self.client.post("/api/items", json={
            "name": f"Transaction {random.randint(10000, 99999)}",
            "value": random.uniform(1.0, 10000.0),
            "category": "transaction"
        })
    
    @task(2)
    def check_balance(self):
        """Check account balance"""
        self.client.get("/api/items")
    
    @task(1)
    def get_transaction(self):
        """Get transaction details"""
        item_id = random.randint(1, 1000)
        self.client.get(f"/api/items/{item_id}")


class ClienteCUser(HttpUser):
    """
    SaaS user simulation
    Traffic pattern: Business hours focused, low off-hours
    """
    wait_time = between(2, 5)
    host = "http://cliente-c.msp-demo.local"
    
    @task(3)
    def list_contacts(self):
        """List contacts/deals"""
        self.client.get("/api/items?category=contacts")
    
    @task(2)
    def create_contact(self):
        """Create new contact"""
        self.client.post("/api/items", json={
            "name": f"Contact {random.randint(1, 1000)}",
            "description": "Sales lead",
            "category": "contacts"
        })
    
    @task(1)
    def update_deal(self):
        """Update deal status"""
        item_id = random.randint(1, 100)
        self.client.put(f"/api/items/{item_id}", json={
            "name": "Updated deal",
            "value": random.uniform(1000.0, 50000.0),
            "category": "deals"
        })
