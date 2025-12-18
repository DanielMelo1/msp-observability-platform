"""
Database models for base API.

Simple CRUD model that can represent different entities
depending on client context (products, transactions, contacts, etc).
"""
from sqlalchemy import Column, Integer, String, DateTime, Float, Text
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.sql import func
from datetime import datetime

Base = declarative_base()


class Item(Base):
    """
    Generic item model used by all clients.
    
    Flexibility allows this model to represent:
    - Cliente A (E-commerce): Products
    - Cliente B (Fintech): Transactions
    - Cliente C (SaaS): Contacts/Deals
    """
    __tablename__ = "items"
    
    id = Column(Integer, primary_key=True, index=True)
    name = Column(String(255), nullable=False, index=True)
    description = Column(Text, nullable=True)
    value = Column(Float, default=0.0)
    category = Column(String(100), nullable=True, index=True)
    status = Column(String(50), default="active", index=True)
    created_at = Column(DateTime, default=func.now(), nullable=False)
    updated_at = Column(DateTime, default=func.now(), onupdate=func.now(), nullable=False)
    
    def __repr__(self):
        return f"<Item(id={self.id}, name='{self.name}', category='{self.category}')>"
