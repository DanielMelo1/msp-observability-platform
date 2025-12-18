"""
CRUD endpoints for items.

Generic REST API that works for all clients.
Context (e-commerce, fintech, saas) is determined by CLIENT_ID env variable.
"""
from fastapi import APIRouter, HTTPException, status, Depends
from pydantic import BaseModel, Field
from typing import List, Optional
from datetime import datetime
import logging

router = APIRouter(prefix="/api")
logger = logging.getLogger(__name__)


class ItemCreate(BaseModel):
    """Request model for creating items."""
    name: str = Field(..., min_length=1, max_length=255)
    description: Optional[str] = Field(None, max_length=2000)
    value: float = Field(default=0.0, ge=0)
    category: Optional[str] = Field(None, max_length=100)


class ItemResponse(BaseModel):
    """Response model for items."""
    id: int
    name: str
    description: Optional[str]
    value: float
    category: Optional[str]
    status: str
    created_at: datetime
    updated_at: datetime


# In-memory storage for demo purposes
# In production, this would be SQLAlchemy database operations
items_store = {}
item_counter = 0


@router.post("/items", response_model=ItemResponse, status_code=status.HTTP_201_CREATED)
async def create_item(item: ItemCreate):
    """
    Create a new item.
    
    This endpoint handles:
    - Cliente A: Creating products
    - Cliente B: Recording transactions
    - Cliente C: Adding contacts/deals
    """
    global item_counter
    item_counter += 1
    
    new_item = {
        "id": item_counter,
        "name": item.name,
        "description": item.description,
        "value": item.value,
        "category": item.category,
        "status": "active",
        "created_at": datetime.utcnow(),
        "updated_at": datetime.utcnow()
    }
    
    items_store[item_counter] = new_item
    logger.info(f"Item created: {item_counter}")
    
    return new_item


@router.get("/items", response_model=List[ItemResponse])
async def list_items(
    category: Optional[str] = None,
    status: Optional[str] = "active",
    limit: int = 50
):
    """
    List items with optional filtering.
    
    Query parameters:
    - category: Filter by category
    - status: Filter by status (default: active)
    - limit: Maximum items to return (default: 50)
    """
    filtered_items = list(items_store.values())
    
    if category:
        filtered_items = [i for i in filtered_items if i.get("category") == category]
    
    if status:
        filtered_items = [i for i in filtered_items if i.get("status") == status]
    
    logger.info(f"Listed {len(filtered_items[:limit])} items")
    return filtered_items[:limit]


@router.get("/items/{item_id}", response_model=ItemResponse)
async def get_item(item_id: int):
    """Get single item by ID."""
    item = items_store.get(item_id)
    
    if not item:
        logger.warning(f"Item not found: {item_id}")
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Item {item_id} not found"
        )
    
    return item


@router.put("/items/{item_id}", response_model=ItemResponse)
async def update_item(item_id: int, item: ItemCreate):
    """Update existing item."""
    existing_item = items_store.get(item_id)
    
    if not existing_item:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Item {item_id} not found"
        )
    
    existing_item.update({
        "name": item.name,
        "description": item.description,
        "value": item.value,
        "category": item.category,
        "updated_at": datetime.utcnow()
    })
    
    logger.info(f"Item updated: {item_id}")
    return existing_item


@router.delete("/items/{item_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_item(item_id: int):
    """Delete item (soft delete - sets status to inactive)."""
    item = items_store.get(item_id)
    
    if not item:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Item {item_id} not found"
        )
    
    item["status"] = "inactive"
    item["updated_at"] = datetime.utcnow()
    
    logger.info(f"Item deleted: {item_id}")
    return None
