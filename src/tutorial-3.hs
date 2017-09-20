{-# LANGUAGE DeriveGeneric      #-}
{-# LANGUAGE FlexibleInstances  #-}
{-# LANGUAGE OverloadedStrings  #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE TypeApplications   #-}
{-# LANGUAGE TypeFamilies       #-}
module Tutorial3 where

import           Control.Lens
import           Data.Text                  (Text)
import           Data.Time
import           Database.Beam              as B
import           Database.Beam.Postgres
import           Database.PostgreSQL.Simple

data UserT f = User
  { _userEmail     :: Columnar f Text
  , _userFirstName :: Columnar f Text
  , _userLastName  :: Columnar f Text
  , _userPassword  :: Columnar f Text
  } deriving (Generic)

type User = UserT Identity
type UserId = PrimaryKey UserT Identity

deriving instance Show User

instance Beamable UserT
instance Beamable (PrimaryKey UserT)

instance Table UserT where
  data PrimaryKey UserT f = UserId (Columnar f Text) deriving Generic
  primaryKey = UserId . _userEmail

data AddressT f = Address
  { _addressId       :: C f (Auto Int)
  , _addressAddress1 :: C f Text
  , _addressAddress2 :: C f (Maybe Text)
  , _addressCity     :: C f Text
  , _addressState    :: C f Text
  , _addressZip      :: C f Text
  , _addressForUser  :: PrimaryKey UserT f
  } deriving (Generic)

type Address = AddressT Identity
type AddressId = PrimaryKey AddressT Identity

deriving instance Show UserId
deriving instance Show Address

instance Beamable AddressT
instance Beamable (PrimaryKey AddressT)

instance Table AddressT where
    data PrimaryKey AddressT f = AddressId (Columnar f (Auto Int)) deriving Generic
    primaryKey = AddressId . _addressId

data ProductT f = Product
  { _productId          :: C f (Auto Int)
  , _productTitle       :: C f Text
  , _productDescription :: C f Text
  , _productPrice       :: C f Int {- Price in cents -}
  } deriving (Generic)

type Product = ProductT Identity
type ProductId = PrimaryKey ProductT Identity

deriving instance Show Product

instance Table ProductT where
  data PrimaryKey ProductT f = ProductId (Columnar f (Auto Int)) deriving Generic
  primaryKey = ProductId . _productId

instance Beamable ProductT
instance Beamable (PrimaryKey ProductT)

deriving instance Show (PrimaryKey AddressT Identity)

data OrderT f = Order
  { _orderId            :: Columnar f (Auto Int)
  , _orderDate          :: Columnar f LocalTime
  , _orderForUser       :: PrimaryKey UserT f
  , _orderShipToAddress :: PrimaryKey AddressT f
  , _orderShippingInfo  :: PrimaryKey ShippingInfoT (Nullable f)
  } deriving (Generic)

type Order = OrderT Identity
deriving instance Show Order

instance Table OrderT where
    data PrimaryKey OrderT f = OrderId (Columnar f (Auto Int))
                               deriving Generic
    primaryKey = OrderId . _orderId

instance Beamable OrderT
instance Beamable (PrimaryKey OrderT)

data ShippingCarrier
  = USPS
  | FedEx
  | UPS
  | DHL
  deriving (Show, Read, Eq, Ord, Enum)

data ShippingInfoT f = ShippingInfo
  { _shippingInfoId             :: Columnar f (Auto Int)
  , _shippingInfoCarrier        :: Columnar f ShippingCarrier
  , _shippingInfoTrackingNumber :: Columnar f Text
  } deriving (Generic)

type ShippingInfo = ShippingInfoT Identity
deriving instance Show ShippingInfo

instance Table ShippingInfoT where
    data PrimaryKey ShippingInfoT f = ShippingInfoId (Columnar f (Auto Int))
                                      deriving Generic
    primaryKey = ShippingInfoId . _shippingInfoId

instance Beamable ShippingInfoT
instance Beamable (PrimaryKey ShippingInfoT)
deriving instance Show (PrimaryKey ShippingInfoT (Nullable Identity))

deriving instance Show (PrimaryKey OrderT Identity)
deriving instance Show (PrimaryKey ProductT Identity)

data LineItemT f = LineItem
  { _lineItemInOrder    :: PrimaryKey OrderT f
  , _lineItemForProduct :: PrimaryKey ProductT f
  , _lineItemQuantity   :: Columnar f Int
  } deriving (Generic)

type LineItem = LineItemT Identity
deriving instance Show LineItem

instance Table LineItemT where
    data PrimaryKey LineItemT f = LineItemId (PrimaryKey OrderT f) (PrimaryKey ProductT f)
                                  deriving Generic
    primaryKey = LineItemId <$> _lineItemInOrder <*> _lineItemForProduct

instance Beamable LineItemT
instance Beamable (PrimaryKey LineItemT)

data ShoppingCartDb f = ShoppingCartDb
  { _shoppingCartUsers         :: f (TableEntity UserT)
  , _shoppingCartUserAddresses :: f (TableEntity AddressT)
  , _shoppingCartProducts      :: f (TableEntity ProductT)
  , _shoppingCartOrders        :: f (TableEntity OrderT)
  , _shoppingCartShippingInfos :: f (TableEntity ShippingInfoT)
  , _shoppingCartLineItems     :: f (TableEntity LineItemT)
  } deriving (Generic)

instance Database ShoppingCartDb

shoppingCartDb :: DatabaseSettings be ShoppingCartDb
shoppingCartDb = defaultDbSettings

Address (LensFor addressId)    (LensFor addressLine1)
        (LensFor addressLine2) (LensFor addressCity)
        (LensFor addressState) (LensFor addressZip)
        (UserId (LensFor addressForUserId)) = tableLenses

User (LensFor userEmail)    (LensFor userFirstName)
     (LensFor userLastName) (LensFor userPassword) = tableLenses

ShoppingCartDb (TableLens shoppingCartUsers)
               (TableLens shoppingCartUserAddresses) = dbLenses

allUsers :: Q PgSelectSyntax ShoppingCartDb s (UserT (QExpr PgExpressionSyntax s))
allUsers = all_ (shoppingCartDb ^. shoppingCartUsers)

allAddresses :: Q PgSelectSyntax ShoppingCartDb s (AddressT (QExpr PgExpressionSyntax s))
allAddresses = all_ (shoppingCartDb ^. shoppingCartUserAddresses)

james :: User
james = User "james@example.com" "James" "Smith" "b4cc344d25a2efe540adbf2678e2304c"

betty :: User
betty = User "betty@example.com" "Betty" "Jones" "82b054bd83ffad9b6cf8bdb98ce3cc2f"

sam :: User
sam = User "sam@example.com" "Sam" "Taylor" "332532dcfaa1cbf61e2a266bd723612c"

insertUsers :: Connection -> IO ()
insertUsers conn =
  withDatabaseDebug putStrLn conn $ B.runInsert $
    B.insert (_shoppingCartUsers shoppingCartDb) $
    insertValues [james, betty, sam]

insertAddresses :: Connection -> IO ()
insertAddresses conn =
  withDatabaseDebug putStrLn conn $ B.runInsert $
    B.insert (_shoppingCartUserAddresses shoppingCartDb) $
    insertValues [ Address (Auto Nothing) "123 Little Street" Nothing "Boston" "MA" "12345" (pk james)
                 , Address (Auto Nothing) "222 Main Street" (Just "Ste 1") "Houston" "TX" "8888" (pk betty)
                 , Address (Auto Nothing) "9999 Residence Ave" Nothing "Sugarland" "TX" "8989" (pk betty)
                 ]

selectAllUsers :: Connection -> IO ()
selectAllUsers conn =
  withDatabaseDebug putStrLn conn $ do
    users <- runSelectReturningList $ select allUsers
    mapM_ (liftIO . putStrLn . show) users


selectAllUsersAndAddresses :: Connection -> IO ([(User, Address)])
selectAllUsersAndAddresses conn =
  withDatabaseDebug putStrLn conn $ runSelectReturningList $ select $ do
    address <- allAddresses
    user <- related_ (shoppingCartDb ^. shoppingCartUsers) (_addressForUser address)
    return (user, address)

bettyEmail :: Text
bettyEmail = "betty@example.com"

selectAddressForBetty :: Connection -> IO [Address]
selectAddressForBetty conn =
  withDatabaseDebug putStrLn conn $
    runSelectReturningList $ select $ do
      address <- all_ (shoppingCartDb ^. shoppingCartUserAddresses)
      guard_ (address ^. addressForUserId ==. val_ bettyEmail)
      return address

updatingUserWithSave :: Connection -> IO ()
updatingUserWithSave conn = do
  [james] <- withDatabaseDebug putStrLn conn $
             do
               runUpdate $
                 save (shoppingCartDb ^. shoppingCartUsers) (james {_userPassword = "52a516ca6df436828d9c0d26e31ef704" })

               runSelectReturningList $
                 B.lookup (shoppingCartDb ^. shoppingCartUsers) (UserId "james@example.com")

  putStrLn ("James's new password is " ++ show (james ^. userPassword))

updatingAddressesWithFinerGrainedControl :: Connection -> IO ()
updatingAddressesWithFinerGrainedControl conn = do
  addresses <- withDatabaseDebug putStrLn conn $
               do
                 runUpdate $
                    update (shoppingCartDb ^. shoppingCartUserAddresses)
                           (\address -> [ address ^. addressCity <-. val_ "Sugarville"
                                        , address ^. addressZip <-. "12345"])
                           (\address -> address ^. addressCity ==. val_ "Sugarland" &&.
                                        address ^. addressState ==. val_ "TX")
                 runSelectReturningList $ select $ all_ (shoppingCartDb ^. shoppingCartUserAddresses)

  mapM_ print addresses

sortUsersByFirstName :: Connection -> IO ()
sortUsersByFirstName conn =
  withDatabaseDebug putStrLn conn $ do
    users <- runSelectReturningList $ select sortUsersByFirstName
    mapM_ (liftIO . putStrLn . show) users
  where
    sortUsersByFirstName = orderBy_ (\u -> (asc_ (_userFirstName u), desc_ (_userLastName u))) allUsers

boundedUsers :: Connection -> IO ()
boundedUsers conn =
  withDatabaseDebug putStrLn conn $ do
    users <- runSelectReturningList $ select boundedQuery
    mapM_ (liftIO . putStrLn . show) users
  where
    boundedQuery = limit_ 1 $ offset_ 1 $ orderBy_ (asc_ . _userFirstName) $ allUsers

userCount :: Connection -> IO ()
userCount conn =
  withDatabaseDebug putStrLn conn $ do
    Just c <- runSelectReturningOne $ select userCount
    liftIO $ putStrLn ("We have " ++ show c ++ " users in the database")
  where
    userCount = aggregate_ (\u -> as_ @Int countAll_) allUsers

numberOfUsersByName :: Connection -> IO ()
numberOfUsersByName conn =
  withDatabaseDebug putStrLn conn $ do
    countedByName <- runSelectReturningList $ select numberOfUsersByName
    mapM_ (liftIO . putStrLn . show) countedByName
  where
    numberOfUsersByName = aggregate_ (\u -> (group_ (_userFirstName u), as_ @Int countAll_)) allUsers

main :: IO ()
main = do
  conn <- connectPostgreSQL "host=localhost dbname=shoppingcart2"
  return ()