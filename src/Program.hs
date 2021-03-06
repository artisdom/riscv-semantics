{-# LANGUAGE MultiParamTypeClasses, FunctionalDependencies, FlexibleInstances, UndecidableInstances, ScopedTypeVariables #-}
module Program where
import CSRField
import Decode
import Utility
import Data.Int
import Data.Bits
import Control.Monad
import Control.Monad.Trans
import Control.Monad.Trans.Maybe
import Prelude

-- Note that this is ordered: User < Supervisor < Machine
data PrivMode = User | Supervisor | Machine deriving (Eq, Ord, Show)

decodePrivMode 0 = User
decodePrivMode 1 = Supervisor
decodePrivMode 3 = Machine
decodePrivMode _ = error "Invalid privilege mode"

encodePrivMode User = 0
encodePrivMode Supervisor = 1
encodePrivMode Machine = 3

class (Monad p, MachineWidth t) => RiscvProgram p t | p -> t where
  getRegister :: Register -> p t
  setRegister :: Register -> t -> p ()
  loadByte :: t -> p Int8
  loadHalf :: t -> p Int16
  loadWord :: t -> p Int32
  loadDouble :: t -> p Int64
  storeByte :: t -> Int8 -> p ()
  storeHalf :: t -> Int16 -> p ()
  storeWord :: t -> Int32 -> p ()
  storeDouble :: t -> Int64 -> p ()
  getCSRField :: CSRField -> p MachineInt
  setCSRField :: (Integral s) => CSRField -> s -> p ()
  getPC :: p t
  setPC :: t -> p ()
  getPrivMode :: p PrivMode
  setPrivMode :: PrivMode -> p ()
  commit :: p ()
  endCycle :: forall t. p t

getXLEN :: forall p t s. (RiscvProgram p t, Integral s) => p s
getXLEN = do
            mxl <- getCSRField MXL
            case mxl of
                1 -> return 32
                2 -> return 64

instance (RiscvProgram p t) => RiscvProgram (MaybeT p) t where
  getRegister r = lift (getRegister r)
  setRegister r v = lift (setRegister r v)
  loadByte a = lift (loadByte a)
  loadHalf a = lift (loadHalf a)
  loadWord a = lift (loadWord a)
  loadDouble a = lift (loadDouble a)
  storeByte a v = lift (storeByte a v)
  storeHalf a v = lift (storeHalf a v)
  storeWord a v = lift (storeWord a v)
  storeDouble a v = lift (storeDouble a v)
  getCSRField f = lift (getCSRField f)
  setCSRField f v = lift (setCSRField f v)
  getPC = lift getPC
  setPC v = lift (setPC v)
  getPrivMode = lift getPrivMode
  setPrivMode m = lift (setPrivMode m)
  commit = lift commit
  endCycle = MaybeT (return Nothing)

raiseException :: forall a p t. (RiscvProgram p t) => MachineInt -> MachineInt -> p a
raiseException isInterrupt exceptionCode = do
  pc <- getPC
  addr <- getCSRField MTVecBase
  setCSRField MEPC pc
  setCSRField MCauseInterrupt isInterrupt
  setCSRField MCauseCode exceptionCode
  setPC ((fromIntegral:: MachineInt -> t) addr * 4)
  endCycle

